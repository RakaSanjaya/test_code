defmodule MessagingGateway.Repo.Migrations.CreateTenants do
  use Ecto.Migration

  def change do
    create table(:tenants) do
      add :name, :string, null: false
      add :balance, :bigint, null: false, default: 0
      add :status, :string, null: false, default: "active"
      timestamps()
    end

    create constraint(:tenants, :tenants_balance_non_negative, check: "balance >= 0")

    create constraint(:tenants, :tenants_status_valid, check: "status IN ('active', 'suspended')")
  end
end
