defmodule MessagingGateway.Repo.Migrations.CreateTemplates do
  use Ecto.Migration

  def change do
    create table(:templates) do
      add :tenant_id, references(:tenants, on_delete: :restrict), null: false
      add :code, :string, null: false
      add :category, :string, null: false
      add :body_pattern, :text, null: false
      add :status, :string, null: false, default: "pending"
      timestamps()
    end

    create unique_index(:templates, [:tenant_id, :code])

    create constraint(:templates, :templates_category_valid,
             check: "category IN ('authentication', 'utility', 'marketing')"
           )

    create constraint(:templates, :templates_status_valid,
             check: "status IN ('approved', 'pending', 'rejected')"
           )
  end
end
