defmodule MessagingGateway.Messaging.StatusUpdateTest do
  use MessagingGateway.DataCase, async: true

  alias MessagingGateway.Accounts.Tenant
  alias MessagingGateway.Billing.BalanceTransaction
  alias MessagingGateway.Messaging

  setup do
    t = tenant_fixture(%{balance: 10_000})
    ch = channel_fixture(t)
    m = message_fixture(t, ch, %{cost: 500})
    %{t: t, ch: ch, m: m}
  end

  defp balance(t), do: Repo.get!(Tenant, t.id).balance

  defp refunds(m) do
    Repo.aggregate(
      from(x in BalanceTransaction, where: x.message_id == ^m.id and x.type == "refund"),
      :count
    )
  end

  test "queued -> sent changes status only", %{t: t, m: m} do
    assert {:ok, :updated, %{status: "sent"}} = Messaging.apply_status_update(m.id, "sent", nil)
    assert balance(t) == 10_000 and refunds(m) == 0
  end

  test "sent -> failed refunds cost and stores the reason", %{t: t, m: m} do
    {:ok, :updated, _} = Messaging.apply_status_update(m.id, "sent", nil)

    assert {:ok, :updated, %{status: "failed", failure_reason: "recipient_unreachable"}} =
             Messaging.apply_status_update(m.id, "failed", "recipient_unreachable")

    assert balance(t) == 10_500 and refunds(m) == 1
  end

  test "queued -> failed also refunds", %{t: t, m: m} do
    {:ok, :updated, _} = Messaging.apply_status_update(m.id, "failed", nil)
    assert balance(t) == 10_500
  end

  test "repeating a final status is a no-op without a second refund", %{t: t, m: m} do
    {:ok, :updated, _} = Messaging.apply_status_update(m.id, "failed", "x")

    assert {:ok, :unchanged, %{status: "failed"}} =
             Messaging.apply_status_update(m.id, "failed", "x")

    assert balance(t) == 10_500 and refunds(m) == 1
  end

  test "illegal transitions are rejected without refund", %{m: m} do
    assert {:error, :invalid_transition} = Messaging.apply_status_update(m.id, "delivered", nil)
    {:ok, :updated, _} = Messaging.apply_status_update(m.id, "sent", nil)
    {:ok, :updated, _} = Messaging.apply_status_update(m.id, "delivered", nil)
    assert {:error, :invalid_transition} = Messaging.apply_status_update(m.id, "failed", "late")
    assert refunds(m) == 0
  end

  test "unknown/malformed ids and non-vendor statuses", %{m: m} do
    for id <- [Ecto.UUID.generate(), "not-a-uuid", nil],
        do: assert({:error, :not_found} = Messaging.apply_status_update(id, "sent", nil))

    for s <- ["queued", "read", ""],
        do: assert({:error, :invalid_status} = Messaging.apply_status_update(m.id, s, nil))
  end
end
