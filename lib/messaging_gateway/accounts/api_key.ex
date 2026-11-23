defmodule MessagingGateway.Accounts.ApiKey do
  @moduledoc """
  API credential. `client_key` is public; only a peppered HMAC of the secret is stored.
  """
  use MessagingGateway.Schema

  alias MessagingGateway.Accounts.Tenant

  @scopes ~w(messages:write messages:read)

  schema "api_keys" do
    belongs_to :tenant, Tenant
    field :name, :string
    field :client_key, :string
    field :secret_hash, :string, redact: true
    field :scopes, {:array, :string}, default: []
    field :active, :boolean, default: true
    timestamps()
  end

  def scopes, do: @scopes

  @spec has_scope?(%__MODULE__{}, String.t()) :: boolean()
  def has_scope?(%__MODULE__{scopes: scopes}, scope) when is_list(scopes), do: scope in scopes
  def has_scope?(_, _), do: false

  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:tenant_id, :name, :client_key, :secret_hash, :scopes, :active])
    |> validate_required([:tenant_id, :client_key, :secret_hash, :scopes, :active])
    |> validate_subset(:scopes, @scopes)
    |> validate_format(:secret_hash, ~r/\A[0-9a-f]{64}\z/)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint(:client_key)
    |> check_constraint(:scopes, name: :api_keys_scopes_valid)
  end
end
