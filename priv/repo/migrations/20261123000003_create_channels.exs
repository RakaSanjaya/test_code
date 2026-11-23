defmodule MessagingGateway.Repo.Migrations.CreateChannels do
  use Ecto.Migration

  def change do
    create table(:channels) do
      add :tenant_id, references(:tenants, on_delete: :restrict), null: false
      add :type, :string, null: false
      add :name, :string, null: false
      add :default_category, :string, null: false
      add :active, :boolean, null: false, default: true
      timestamps()
    end

    # Target of the composite (channel_id, tenant_id) foreign key on messages.
    create unique_index(:channels, [:id, :tenant_id])
    create index(:channels, [:tenant_id])

    create constraint(:channels, :channels_type_valid, check: "type IN ('whatsapp', 'sms')")

    create constraint(:channels, :channels_default_category_valid,
             check: "default_category IN ('authentication', 'utility', 'marketing')"
           )
  end
end
