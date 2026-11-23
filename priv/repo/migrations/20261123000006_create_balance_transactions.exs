defmodule MessagingGateway.Repo.Migrations.CreateBalanceTransactions do
  use Ecto.Migration

  def change do
    create table(:balance_transactions) do
      add :tenant_id, references(:tenants, on_delete: :restrict), null: false

      add :message_id,
          references(:messages,
            with: [tenant_id: :tenant_id],
            match: :full,
            on_delete: :restrict
          ),
          null: false

      add :type, :string, null: false
      add :amount, :bigint, null: false
      add :balance_after, :bigint, null: false
      timestamps(updated_at: false)
    end

    # At most one debit and one refund per message: the last line of defence against double refunds.
    create unique_index(:balance_transactions, [:message_id, :type])
    create index(:balance_transactions, [:tenant_id])

    create constraint(:balance_transactions, :balance_transactions_type_valid,
             check: "type IN ('debit', 'refund')"
           )

    create constraint(:balance_transactions, :balance_transactions_amount_positive,
             check: "amount > 0"
           )

    create constraint(:balance_transactions, :balance_transactions_balance_after_non_negative,
             check: "balance_after >= 0"
           )
  end
end
