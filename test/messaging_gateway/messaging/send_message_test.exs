defmodule MessagingGateway.Messaging.SendMessageTest do
  use MessagingGateway.DataCase, async: true
  use Oban.Testing, repo: MessagingGateway.Repo

  alias MessagingGateway.Accounts.Tenant
  alias MessagingGateway.Billing.BalanceTransaction
  alias MessagingGateway.Messaging
  alias MessagingGateway.Messaging.Message

  setup do
    a = tenant_fixture(%{balance: 10_000})
    b = tenant_fixture(%{balance: 10_000})
    ch_a = channel_fixture(a, %{default_category: "utility"})
    ch_b = channel_fixture(b)

    template_fixture(a, %{
      code: "otp_login_v1",
      category: "authentication",
      body_pattern: "Kode OTP Anda adalah {{1}}"
    })

    template_fixture(b, %{
      code: "otp_login_v1",
      category: "marketing",
      body_pattern: "Kode OTP Anda adalah {{1}}"
    })

    template_fixture(b, %{code: "promo_b", category: "marketing", body_pattern: "Promo {{1}}"})

    template_fixture(a, %{
      code: "promo_pending",
      category: "marketing",
      status: "pending",
      body_pattern: "Promo {{1}}"
    })

    %{a: a, b: b, ch_a: ch_a, ch_b: ch_b}
  end

  defp p(ch, extra \\ %{}) do
    Map.merge(
      %{"channel_id" => ch.id, "recipient" => "+6281234567890", "text" => "Pesanan Anda dikirim"},
      extra
    )
  end

  defp otp(ch),
    do: p(ch, %{"template_code" => "otp_login_v1", "text" => "Kode OTP Anda adalah 849201"})

  defp balance(t), do: Repo.get!(Tenant, t.id).balance
  defp ledger(t), do: Repo.all(from x in BalanceTransaction, where: x.tenant_id == ^t.id)
  defp messages(t), do: Repo.all(from x in Message, where: x.tenant_id == ^t.id)

  test "plain text uses channel default category, debits, records ledger and enqueues dispatch",
       %{a: a, ch_a: ch} do
    assert {:ok, m, :created} = Messaging.send_message(a, p(ch), nil)

    assert %{
             category: "utility",
             cost: 500,
             status: "queued",
             content: "Pesanan Anda dikirim",
             tenant_id: tid
           } = m

    assert tid == a.id and balance(a) == 9_500
    assert [%{type: "debit", amount: 500, balance_after: 9_500}] = ledger(a)
    assert_enqueued(worker: MessagingGateway.Dispatch.Worker, args: %{"message_id" => m.id})
  end

  test "approved template decides the category (and the tenant's own template wins)",
       %{a: a, ch_a: ch} do
    assert {:ok, %{category: "authentication", cost: 300, template_code: "otp_login_v1"},
            :created} =
             Messaging.send_message(a, otp(ch), nil)
  end

  test "client cannot tamper with price, category, status or tenant (root or metadata)",
       %{a: a, b: b, ch_a: ch} do
    evil = %{
      "category" => "authentication",
      "cost" => 1,
      "price" => 1,
      "status" => "delivered",
      "tenant_id" => b.id
    }

    params = p(ch, Map.put(evil, "metadata", Map.put(evil, "reference_id", "order-123")))
    assert {:ok, m, :created} = Messaging.send_message(a, params, nil)

    assert %{
             category: "utility",
             cost: 500,
             status: "queued",
             metadata: %{"reference_id" => "order-123"} = md
           } = m

    assert m.tenant_id == a.id and map_size(md) == 1
  end

  test "cross-tenant and missing channels look identical", %{a: a, ch_b: ch_b} do
    assert {:error, :channel_not_found} = Messaging.send_message(a, p(ch_b), nil)

    assert {:error, :channel_not_found} =
             Messaging.send_message(a, p(%{id: Ecto.UUID.generate()}), nil)

    assert balance(a) == 10_000 and ledger(a) == []
  end

  test "inactive own channel", %{a: a} do
    assert {:error, :channel_inactive} =
             Messaging.send_message(a, p(channel_fixture(a, %{active: false})), nil)
  end

  test "template rules: foreign, pending, mismatched text", %{a: a, ch_a: ch} do
    assert {:error, :template_not_found} =
             Messaging.send_message(
               a,
               p(ch, %{"template_code" => "promo_b", "text" => "Promo x"}),
               nil
             )

    assert {:error, :template_not_approved} =
             Messaging.send_message(
               a,
               p(ch, %{"template_code" => "promo_pending", "text" => "Promo x"}),
               nil
             )

    assert {:error, :template_mismatch} =
             Messaging.send_message(
               a,
               p(ch, %{"template_code" => "otp_login_v1", "text" => "DISKON 90% hari ini!"}),
               nil
             )

    assert balance(a) == 10_000
  end

  test "insufficient balance writes nothing; exact balance succeeds" do
    t = tenant_fixture(%{balance: 499})
    ch = channel_fixture(t)
    assert {:error, :insufficient_balance} = Messaging.send_message(t, p(ch), nil)
    assert balance(t) == 499 and ledger(t) == [] and messages(t) == []

    t2 = tenant_fixture(%{balance: 500})
    assert {:ok, _, :created} = Messaging.send_message(t2, p(channel_fixture(t2)), nil)
    assert balance(t2) == 0
  end

  test "same Idempotency-Key replays without a second charge", %{a: a, ch_a: ch} do
    {:ok, m1, :created} = Messaging.send_message(a, p(ch), "order-123")
    assert {:ok, m2, :replayed} = Messaging.send_message(a, p(ch), "order-123")
    assert m1.id == m2.id and balance(a) == 9_500 and length(messages(a)) == 1
  end

  test "replay still works after the balance is drained" do
    t = tenant_fixture(%{balance: 500})
    ch = channel_fixture(t)
    {:ok, m1, :created} = Messaging.send_message(t, p(ch), "k")
    assert {:ok, %{id: id}, :replayed} = Messaging.send_message(t, p(ch), "k")
    assert id == m1.id
  end

  test "same key with a different body is refused", %{a: a, ch_a: ch} do
    {:ok, _, :created} = Messaging.send_message(a, p(ch), "k1")

    assert {:error, :idempotency_key_reused} =
             Messaging.send_message(a, p(ch, %{"text" => "lain"}), "k1")

    assert balance(a) == 9_500
  end

  test "same key in another tenant is independent", %{a: a, b: b, ch_a: ch_a, ch_b: ch_b} do
    assert {:ok, _, :created} = Messaging.send_message(a, p(ch_a), "shared")
    assert {:ok, _, :created} = Messaging.send_message(b, p(ch_b), "shared")
  end

  test "invalid input and invalid key", %{a: a, ch_a: ch} do
    assert {:error, %Ecto.Changeset{}} = Messaging.send_message(a, %{"recipient" => "x"}, nil)
    assert {:error, :invalid_idempotency_key} = Messaging.send_message(a, p(ch), "has space")
  end

  test "tenant suspended after authentication", %{a: a, ch_a: ch} do
    Repo.update_all(from(t in Tenant, where: t.id == ^a.id), set: [status: "suspended"])
    assert {:error, :tenant_suspended} = Messaging.send_message(a, p(ch), nil)
  end
end
