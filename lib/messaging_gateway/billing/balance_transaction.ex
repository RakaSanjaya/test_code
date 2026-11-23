defmodule MessagingGateway.Billing.BalanceTransaction do
  @moduledoc "Append-only balance ledger row: one `debit` and at most one `refund` per message."
  use MessagingGateway.Schema

  alias MessagingGateway.Accounts.Tenant
  alias MessagingGateway.Messaging.Message

  @types ~w(debit refund)

  schema "balance_transactions" do
    belongs_to :tenant, Tenant
    belongs_to :message, Message
    field :type, :string
    field :amount, :integer
    field :balance_after, :integer
    timestamps(updated_at: false)
  end

  def types, do: @types

  def changeset(tx, attrs) do
    tx
    |> cast(attrs, [:tenant_id, :message_id, :type, :amount, :balance_after])
    |> validate_required([:tenant_id, :message_id, :type, :amount, :balance_after])
    |> validate_inclusion(:type, @types)
    |> validate_number(:amount, greater_than: 0)
    |> validate_number(:balance_after, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:message_id, name: :balance_transactions_message_id_fkey)
    |> unique_constraint(:message_id, name: :balance_transactions_message_id_type_index)
    |> check_constraint(:type, name: :balance_transactions_type_valid)
    |> check_constraint(:amount, name: :balance_transactions_amount_positive)
    |> check_constraint(:balance_after, name: :balance_transactions_balance_after_non_negative)
  end
end
