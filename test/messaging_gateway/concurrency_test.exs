defmodule MessagingGateway.ConcurrencyTest do
  @moduledoc """
  Races run on real, independent Postgres connections.

  The SQL sandbox (even in shared mode) funnels every process through one
  connection, which serialises transactions and hides races: a broken
  read-modify-write debit would still pass. So this module bypasses the sandbox
  with `unboxed_run/2` for setup, the races themselves and cleanup, and only
  ever asserts on rows belonging to the tenants it created.
  """
  use ExUnit.Case, async: false

  import Ecto.Query
  import MessagingGateway.Fixtures
  import MessagingGatewayWeb.TestHelpers

  alias Ecto.Adapters.SQL.Sandbox
  alias MessagingGateway.Accounts.Tenant
  alias MessagingGateway.Billing.BalanceTransaction
  alias MessagingGateway.Messaging
  alias MessagingGateway.Messaging.Message
  alias MessagingGateway.Repo

  @moduletag timeout: 120_000

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  # Every task waits at a barrier and is released at once for maximum contention.
  defp race(n, fun) do
    tasks =
      for i <- 1..n do
        Task.async(fn ->
          receive do
            :go -> :ok
          end

          unboxed(fn -> fun.(i) end)
        end)
      end

    Enum.each(tasks, &send(&1.pid, :go))
    Task.await_many(tasks, 30_000)
  end

  defp new_tenant(attrs) do
    tenant = unboxed(fn -> tenant_fixture(attrs) end)
    on_exit(fn -> unboxed(fn -> cleanup(tenant.id) end) end)
    tenant
  end

  defp cleanup(tenant_id) do
    message_ids =
      Repo.all(from m in Message, where: m.tenant_id == ^tenant_id, select: type(m.id, :string))

    Repo.query!("DELETE FROM oban_jobs WHERE args->>'message_id' = ANY($1)", [message_ids])

    for table <- ~w(balance_transactions messages templates channels api_keys) do
      Repo.query!("DELETE FROM #{table} WHERE tenant_id = $1", [Ecto.UUID.dump!(tenant_id)])
    end

    Repo.query!("DELETE FROM tenants WHERE id = $1", [Ecto.UUID.dump!(tenant_id)])
  end

  defp balance(t), do: unboxed(fn -> Repo.get!(Tenant, t.id).balance end)

  defp ledger(t, type) do
    unboxed(fn ->
      Repo.all(from x in BalanceTransaction, where: x.tenant_id == ^t.id and x.type == ^type)
    end)
  end

  defp params(ch),
    do: %{"channel_id" => ch.id, "recipient" => "+6281234567890", "text" => "Halo"}

  defp sent_message_for(t, ch) do
    unboxed(fn ->
      {:ok, m, :created} = Messaging.send_message(t, params(ch), nil)
      {:ok, :updated, m} = Messaging.apply_status_update(m.id, "sent", nil)
      m
    end)
  end

  defp sent_message(balance) do
    t = new_tenant(%{balance: balance})
    ch = unboxed(fn -> channel_fixture(t) end)
    {t, sent_message_for(t, ch)}
  end

  test "20 parallel sends with balance for 3 never overdraw" do
    t = new_tenant(%{balance: 1_500})
    ch = unboxed(fn -> channel_fixture(t) end)

    results = race(20, fn _ -> Messaging.send_message(t, params(ch), nil) end)

    assert Enum.count(results, &match?({:ok, _, :created}, &1)) == 3
    assert Enum.count(results, &(&1 == {:error, :insufficient_balance})) == 17
    assert balance(t) == 0
    assert ledger(t, "debit") |> Enum.map(& &1.balance_after) |> Enum.sort() == [0, 500, 1_000]
  end

  test "10 parallel sends with the same Idempotency-Key create one message and one debit" do
    t = new_tenant(%{balance: 10_000})
    ch = unboxed(fn -> channel_fixture(t) end)

    results = race(10, fn _ -> Messaging.send_message(t, params(ch), "race-key-1") end)

    assert Enum.count(results, &match?({:ok, _, :created}, &1)) == 1
    assert Enum.count(results, &match?({:ok, _, :replayed}, &1)) == 9
    assert results |> Enum.map(fn {:ok, m, _} -> m.id end) |> Enum.uniq() |> length() == 1
    assert balance(t) == 9_500 and length(ledger(t, "debit")) == 1
  end

  test "10 parallel 'failed' reports refund exactly once" do
    {t, m} = sent_message(10_000)

    results =
      race(10, fn _ -> Messaging.apply_status_update(m.id, "failed", "recipient_unreachable") end)

    assert Enum.count(results, &match?({:ok, :updated, _}, &1)) == 1
    assert Enum.count(results, &match?({:ok, :unchanged, _}, &1)) == 9
    assert balance(t) == 10_000 and length(ledger(t, "refund")) == 1
  end

  test "racing 'delivered' and 'failed' converge on one final state" do
    {t, m} = sent_message(10_000)

    results =
      race(10, fn i ->
        Messaging.apply_status_update(
          m.id,
          if(rem(i, 2) == 0, do: "delivered", else: "failed"),
          nil
        )
      end)

    assert Enum.count(results, &match?({:ok, :updated, _}, &1)) == 1
    final = unboxed(fn -> Repo.get!(Message, m.id) end).status
    refunds = length(ledger(t, "refund"))
    assert final in ["delivered", "failed"]
    assert refunds == if(final == "failed", do: 1, else: 0)
    assert balance(t) == 9_500 + 500 * refunds
  end

  test "mixed sends and refunds on one tenant finish without deadlock and keep the ledger balanced" do
    t = new_tenant(%{balance: 5_000})
    ch = unboxed(fn -> channel_fixture(t) end)
    sent = for _ <- 1..5, do: sent_message_for(t, ch)

    race(20, fn i ->
      if rem(i, 2) == 0,
        do: Messaging.send_message(t, params(ch), nil),
        else: Messaging.apply_status_update(Enum.at(sent, rem(i, 5)).id, "failed", nil)
    end)

    sum = fn type -> ledger(t, type) |> Enum.map(& &1.amount) |> Enum.sum() end
    assert balance(t) == 5_000 - sum.("debit") + sum.("refund")
    assert balance(t) >= 0
  end

  test "10 parallel HTTP POSTs with balance for 2 -> exactly two 201 and eight 402" do
    t = new_tenant(%{balance: 1_000})
    ch = unboxed(fn -> channel_fixture(t) end)
    {k, s} = unboxed(fn -> api_key_fixture(t) end)

    statuses =
      race(10, fn _ ->
        Phoenix.ConnTest.build_conn()
        |> put_api_auth(k.client_key, s)
        |> post_json("/api/v1/messages", params(ch))
        |> Map.fetch!(:status)
      end)

    assert Enum.frequencies(statuses) == %{201 => 2, 402 => 8}
  end

  test "10 parallel signed 'failed' webhooks (vendor retries) refund exactly once" do
    {t, m} = sent_message(10_000)
    raw = Jason.encode!(%{"message_id" => m.id, "status" => "failed", "reason" => "retry"})
    ts = System.system_time(:second)

    results =
      race(10, fn _ ->
        conn = signed_webhook_post(Phoenix.ConnTest.build_conn(), raw, timestamp: ts)
        {conn.status, Jason.decode!(conn.resp_body)["data"]["result"]}
      end)

    assert Enum.frequencies(results) == %{{200, "updated"} => 1, {200, "unchanged"} => 9}
    assert balance(t) == 10_000 and length(ledger(t, "refund")) == 1
  end
end
