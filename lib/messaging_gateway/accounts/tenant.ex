defmodule MessagingGateway.Accounts.Tenant do
  @moduledoc "A customer of the gateway with a prepaid balance (integer, smallest currency unit)."
  use MessagingGateway.Schema

  @statuses ~w(active suspended)

  schema "tenants" do
    field :name, :string
    field :balance, :integer, default: 0
    field :status, :string, default: "active"
    timestamps()
  end

  def statuses, do: @statuses

  @doc "Internal/seed use only: never cast client-supplied params into a tenant."
  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :balance, :status])
    |> validate_required([:name, :balance, :status])
    |> validate_length(:name, max: 255)
    |> validate_number(:balance, greater_than_or_equal_to: 0)
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:balance, name: :tenants_balance_non_negative)
    |> check_constraint(:status, name: :tenants_status_valid)
  end
end
