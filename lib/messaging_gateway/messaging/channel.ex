defmodule MessagingGateway.Messaging.Channel do
  @moduledoc "A tenant-owned sending channel (WhatsApp/SMS) with a default pricing category."
  use MessagingGateway.Schema

  alias MessagingGateway.Accounts.Tenant
  alias MessagingGateway.Billing.Pricing

  @types ~w(whatsapp sms)

  schema "channels" do
    belongs_to :tenant, Tenant
    field :type, :string
    field :name, :string
    field :default_category, :string
    field :active, :boolean, default: true
    timestamps()
  end

  def types, do: @types

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:tenant_id, :type, :name, :default_category, :active])
    |> validate_required([:tenant_id, :type, :name, :default_category, :active])
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:default_category, Pricing.categories())
    |> foreign_key_constraint(:tenant_id)
    |> check_constraint(:type, name: :channels_type_valid)
    |> check_constraint(:default_category, name: :channels_default_category_valid)
  end
end
