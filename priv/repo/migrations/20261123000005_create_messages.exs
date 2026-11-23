defmodule MessagingGateway.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :tenant_id, references(:tenants, on_delete: :restrict), null: false

      # Composite FK: a message can only point at a channel owned by the same tenant.
      add :channel_id,
          references(:channels,
            with: [tenant_id: :tenant_id],
            match: :full,
            on_delete: :restrict
          ),
          null: false

      add :idempotency_key, :string
      add :request_fingerprint, :string, null: false
      add :recipient, :string, null: false
      add :content, :text, null: false
      add :template_code, :string
      add :category, :string, null: false
      add :cost, :integer, null: false
      add :status, :string, null: false, default: "queued"
      add :metadata, :map, null: false, default: %{}
      add :failure_reason, :string
      timestamps()
    end

    create unique_index(:messages, [:tenant_id, :idempotency_key],
             where: "idempotency_key IS NOT NULL",
             name: :messages_tenant_id_idempotency_key_index
           )

    # Target of the composite (message_id, tenant_id) foreign key on balance_transactions.
    create unique_index(:messages, [:id, :tenant_id])
    create index(:messages, [:tenant_id, :inserted_at])

    create constraint(:messages, :messages_cost_positive, check: "cost > 0")

    create constraint(:messages, :messages_status_valid,
             check: "status IN ('queued', 'sent', 'delivered', 'failed')"
           )

    create constraint(:messages, :messages_category_valid,
             check: "category IN ('authentication', 'utility', 'marketing')"
           )
  end
end
