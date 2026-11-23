defmodule MessagingGateway.Messaging.Template do
  @moduledoc "A tenant-owned message template; its category decides the price when used."
  use MessagingGateway.Schema

  alias MessagingGateway.Accounts.Tenant
  alias MessagingGateway.Billing.Pricing
  alias MessagingGateway.Messaging.TemplateMatcher

  @statuses ~w(approved pending rejected)

  schema "templates" do
    belongs_to :tenant, Tenant
    field :code, :string
    field :category, :string
    field :body_pattern, :string
    field :status, :string, default: "pending"
    timestamps()
  end

  def statuses, do: @statuses

  def changeset(template, attrs) do
    template
    |> cast(attrs, [:tenant_id, :code, :category, :body_pattern, :status])
    |> validate_required([:tenant_id, :code, :category, :body_pattern, :status])
    |> validate_format(:code, ~r/\A[a-z0-9_]{1,64}\z/)
    |> validate_inclusion(:category, Pricing.categories())
    |> validate_inclusion(:status, @statuses)
    |> validate_change(:body_pattern, fn :body_pattern, pattern ->
      if TemplateMatcher.valid_pattern?(pattern),
        do: [],
        else: [body_pattern: "must be at most 1024 bytes with at most 10 {{n}} placeholders"]
    end)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:tenant_id, :code])
    |> check_constraint(:category, name: :templates_category_valid)
    |> check_constraint(:status, name: :templates_status_valid)
  end
end
