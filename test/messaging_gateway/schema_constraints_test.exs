defmodule MessagingGateway.SchemaConstraintsTest do
  use MessagingGateway.DataCase, async: true

  alias MessagingGateway.Accounts.{ApiKey, Tenant}
  alias MessagingGateway.Billing.BalanceTransaction
  alias MessagingGateway.Messaging.Message

  test "tenant balance can never go negative at the DB level" do
    t = tenant_fixture(%{balance: 100})

    assert_raise Postgrex.Error, ~r/tenants_balance_non_negative/, fn ->
      Repo.transaction(fn ->
        Repo.update_all(from(x in Tenant, where: x.id == ^t.id), set: [balance: -1])
      end)
    end
  end

  test "a message cannot reference another tenant's channel (composite FK)" do
    a = tenant_fixture()
    ch_b = channel_fixture(tenant_fixture())

    attrs = %{
      tenant_id: a.id,
      channel_id: ch_b.id,
      request_fingerprint: String.duplicate("0", 64),
      recipient: "+6281234567890",
      content: "x",
      category: "utility",
      cost: 500,
      status: "queued"
    }

    assert {:error, cs} = %Message{} |> Message.create_changeset(attrs) |> Repo.insert()
    assert {_, opts} = cs.errors[:channel_id]
    assert opts[:constraint] == :foreign
  end

  test "idempotency_key is unique per tenant but reusable across tenants" do
    a = tenant_fixture()
    ch_a = channel_fixture(a)
    b = tenant_fixture()
    message_fixture(a, ch_a, %{idempotency_key: "k1"})

    assert_raise Ecto.InvalidChangesetError, fn ->
      message_fixture(a, ch_a, %{idempotency_key: "k1"})
    end

    assert %Message{} = message_fixture(b, channel_fixture(b), %{idempotency_key: "k1"})
  end

  test "ledger accepts exactly one debit and one refund per message" do
    t = tenant_fixture()
    m = message_fixture(t, channel_fixture(t))

    row = fn type ->
      BalanceTransaction.changeset(%BalanceTransaction{}, %{
        tenant_id: t.id,
        message_id: m.id,
        type: type,
        amount: 500,
        balance_after: 9_500
      })
    end

    assert {:ok, _} = Repo.insert(row.("debit"))
    assert {:error, %{errors: [message_id: _]}} = Repo.insert(row.("debit"))
    assert {:ok, _} = Repo.insert(row.("refund"))
    assert {:error, %{errors: [message_id: _]}} = Repo.insert(row.("refund"))
  end

  test "unknown API key scopes are rejected by changeset and by the DB" do
    t = tenant_fixture()

    attrs = %{
      tenant_id: t.id,
      client_key: "ck_x",
      secret_hash: String.duplicate("a", 64),
      scopes: ["admin:all"]
    }

    assert {:error, %{errors: [scopes: _]}} = Repo.insert(ApiKey.changeset(%ApiKey{}, attrs))
    now = DateTime.utc_now()

    assert_raise Postgrex.Error, ~r/api_keys_scopes_valid/, fn ->
      Repo.transaction(fn ->
        Repo.insert_all(ApiKey, [Map.merge(attrs, %{inserted_at: now, updated_at: now})])
      end)
    end
  end

  test "inspect/1 redacts secret_hash, content and recipient" do
    refute inspect(%ApiKey{secret_hash: "deadbeefhash"}) =~ "deadbeefhash"
    out = inspect(%Message{content: "Kode OTP 849201", recipient: "+6281234567890"})
    refute out =~ "849201"
    refute out =~ "+6281234567890"
  end
end
