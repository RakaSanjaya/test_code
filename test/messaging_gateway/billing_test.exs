defmodule MessagingGateway.BillingTest do
  use MessagingGateway.DataCase, async: true

  alias MessagingGateway.Accounts.Tenant
  alias MessagingGateway.Billing
  alias MessagingGateway.Billing.BalanceTransaction

  setup do
    t = tenant_fixture(%{balance: 1_000})
    m = message_fixture(t, channel_fixture(t), %{cost: 300})
    %{t: t, m: m}
  end

  defp in_tx(fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, v} -> v
        {:error, r} -> Repo.rollback(r)
      end
    end)
  end

  test "debit decrements atomically and records balance_after", %{t: t, m: m} do
    assert {:ok, %BalanceTransaction{type: "debit", amount: 300, balance_after: 700}} =
             in_tx(fn -> Billing.debit(t.id, m.id, 300) end)

    assert Repo.get!(Tenant, t.id).balance == 700
  end

  test "debit of the exact balance leaves 0", %{t: t, m: m} do
    assert {:ok, %{balance_after: 0}} = in_tx(fn -> Billing.debit(t.id, m.id, 1_000) end)
  end

  test "debit beyond balance has no side effects", %{t: t, m: m} do
    assert {:error, :insufficient_balance} = in_tx(fn -> Billing.debit(t.id, m.id, 1_001) end)
    assert Repo.get!(Tenant, t.id).balance == 1_000

    assert Repo.aggregate(from(x in BalanceTransaction, where: x.tenant_id == ^t.id), :count) ==
             0
  end

  test "debit on a suspended tenant", %{t: t, m: m} do
    Repo.update_all(from(x in Tenant, where: x.id == ^t.id), set: [status: "suspended"])
    assert {:error, :tenant_suspended} = in_tx(fn -> Billing.debit(t.id, m.id, 1) end)
  end

  test "refund credits once; a second refund is refused", %{t: t, m: m} do
    assert {:ok, %{type: "refund", amount: 300, balance_after: 1_300}} =
             in_tx(fn -> Billing.refund(t.id, m.id, 300) end)

    assert {:error, :already_refunded} = in_tx(fn -> Billing.refund(t.id, m.id, 300) end)
    assert Repo.get!(Tenant, t.id).balance == 1_300
  end

  test "billing functions refuse to run outside a transaction", %{t: t, m: m} do
    assert_raise ArgumentError, fn -> Billing.debit(t.id, m.id, 1) end
    assert_raise ArgumentError, fn -> Billing.refund(t.id, m.id, 1) end
  end
end
