defmodule MessagingGateway.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys) do
      add :tenant_id, references(:tenants, on_delete: :restrict), null: false
      add :name, :string
      add :client_key, :string, null: false
      add :secret_hash, :string, null: false
      add :scopes, {:array, :string}, null: false, default: []
      add :active, :boolean, null: false, default: true
      timestamps()
    end

    create unique_index(:api_keys, [:client_key])
    create index(:api_keys, [:tenant_id])

    create constraint(:api_keys, :api_keys_scopes_valid,
             check: "scopes <@ ARRAY['messages:write', 'messages:read']::varchar[]"
           )
  end
end
