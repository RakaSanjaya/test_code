defmodule MessagingGateway.Messaging.Message do
  @moduledoc """
  An outbound message. Category and cost are always resolved server-side; `content`
  and `recipient` are redacted from `inspect/1` so they never reach crash logs.
  """
  use MessagingGateway.Schema

  alias MessagingGateway.Accounts.Tenant
  alias MessagingGateway.Billing.Pricing
  alias MessagingGateway.Messaging.Channel

  @statuses ~w(queued sent delivered failed)

  schema "messages" do
    belongs_to :tenant, Tenant
    belongs_to :channel, Channel
    field :idempotency_key, :string
    field :request_fingerprint, :string
    field :recipient, :string, redact: true
    field :content, :string, redact: true
    field :template_code, :string
    field :category, :string
    field :cost, :integer
    field :status, :string, default: "queued"
    field :metadata, :map, default: %{}
    field :failure_reason, :string
    timestamps()
  end

  def statuses, do: @statuses

  @fields ~w(tenant_id channel_id idempotency_key request_fingerprint recipient content
             template_code category cost status metadata)a

  @required ~w(tenant_id channel_id request_fingerprint recipient content category cost status)a

  @doc "Internal: built from already-validated, server-resolved attributes."
  def create_changeset(message, attrs) do
    message
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:category, Pricing.categories())
    |> validate_number(:cost, greater_than: 0)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:channel_id, name: :messages_channel_id_fkey)
    |> unique_constraint(:idempotency_key, name: :messages_tenant_id_idempotency_key_index)
    |> check_constraint(:cost, name: :messages_cost_positive)
    |> check_constraint(:status, name: :messages_status_valid)
    |> check_constraint(:category, name: :messages_category_valid)
  end
end
