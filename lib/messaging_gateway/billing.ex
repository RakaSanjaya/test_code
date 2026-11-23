defmodule MessagingGateway.Billing do
  @moduledoc """
  Balance mutations. Both functions must run inside a database transaction, and a
  returned `{:error, _}` obliges the caller to roll that transaction back.

  * Debit is a single conditional `UPDATE ... WHERE balance >= amount`, so the
    check and the decrement are one atomic row operation: concurrent requests
    serialise on the tenant row and can never overdraw (backstopped by the
    `tenants_balance_non_negative` CHECK).
  * Refund relies on its caller holding the message row lock; the unique
    `(message_id, type)` ledger index is the last line of defence.
  """

  import Ecto.Query

  alias MessagingGateway.Accounts.Tenant
  alias MessagingGateway.Billing.BalanceTransaction
  alias MessagingGateway.Repo

  @spec debit(Ecto.UUID.t(), Ecto.UUID.t(), pos_integer()) ::
          {:ok, BalanceTransaction.t()} | {:error, :insufficient_balance | :tenant_suspended}
  def debit(tenant_id, message_id, amount) when is_integer(amount) and amount > 0 do
    ensure_transaction!()

    query =
      from t in Tenant,
        where: t.id == ^tenant_id and t.status == "active" and t.balance >= ^amount,
        select: t.balance

    case Repo.update_all(query, inc: [balance: -amount], set: [updated_at: DateTime.utc_now()]) do
      {1, [balance_after]} ->
        record(tenant_id, message_id, "debit", amount, balance_after)

      {0, []} ->
        status = Repo.one(from t in Tenant, where: t.id == ^tenant_id, select: t.status)

        if status == "active",
          do: {:error, :insufficient_balance},
          else: {:error, :tenant_suspended}
    end
  end

  @spec refund(Ecto.UUID.t(), Ecto.UUID.t(), pos_integer()) ::
          {:ok, BalanceTransaction.t()} | {:error, :already_refunded}
  def refund(tenant_id, message_id, amount) when is_integer(amount) and amount > 0 do
    ensure_transaction!()

    query = from t in Tenant, where: t.id == ^tenant_id, select: t.balance

    {1, [balance_after]} =
      Repo.update_all(query, inc: [balance: amount], set: [updated_at: DateTime.utc_now()])

    case record(tenant_id, message_id, "refund", amount, balance_after) do
      {:ok, tx} -> {:ok, tx}
      {:error, _changeset} -> {:error, :already_refunded}
    end
  end

  defp record(tenant_id, message_id, type, amount, balance_after) do
    %BalanceTransaction{}
    |> BalanceTransaction.changeset(%{
      tenant_id: tenant_id,
      message_id: message_id,
      type: type,
      amount: amount,
      balance_after: balance_after
    })
    |> Repo.insert()
  end

  defp ensure_transaction! do
    unless Repo.in_transaction?() do
      raise ArgumentError, "billing operations must run inside a database transaction"
    end
  end
end
