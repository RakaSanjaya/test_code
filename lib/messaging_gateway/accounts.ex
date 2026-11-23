defmodule MessagingGateway.Accounts do
  @moduledoc "Tenants and API key authentication."

  import Ecto.Query

  alias MessagingGateway.Accounts.{ApiKey, Secret, Tenant}
  alias MessagingGateway.Repo

  @max_credential_bytes 256

  @spec create_tenant(map()) :: {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()}
  def create_tenant(attrs), do: %Tenant{} |> Tenant.changeset(attrs) |> Repo.insert()

  @doc """
  Creates an API key. The plaintext secret is returned exactly once; only its hash is stored.
  """
  @spec create_api_key(Tenant.t(), map()) ::
          {:ok, ApiKey.t(), String.t()} | {:error, Ecto.Changeset.t()}
  def create_api_key(%Tenant{id: tenant_id}, attrs) do
    secret = Secret.generate_secret()

    params = %{
      tenant_id: tenant_id,
      name: Map.get(attrs, :name),
      client_key: Secret.generate_client_key(),
      secret_hash: Secret.hash(secret),
      scopes: Map.get(attrs, :scopes, []),
      active: Map.get(attrs, :active, true)
    }

    case %ApiKey{} |> ApiKey.changeset(params) |> Repo.insert() do
      {:ok, key} -> {:ok, key, secret}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Verifies a client key + secret pair in constant time.

  Every failure (unknown key, wrong secret, inactive key, malformed input) is
  `:unauthorized`. Tenant suspension is only revealed once the secret is proven.
  """
  @spec authenticate(term(), term()) ::
          {:ok, ApiKey.t()} | {:error, :unauthorized | :tenant_suspended}
  def authenticate(client_key, secret) do
    if credential?(client_key) and credential?(secret) do
      do_authenticate(client_key, secret)
    else
      {:error, :unauthorized}
    end
  end

  defp do_authenticate(client_key, secret) do
    query = from k in ApiKey, where: k.client_key == ^client_key, preload: [:tenant]

    case Repo.one(query) do
      nil ->
        Secret.dummy_verify(secret)
        {:error, :unauthorized}

      %ApiKey{} = key ->
        valid? = Secret.verify(secret, key.secret_hash)

        cond do
          not valid? or not key.active -> {:error, :unauthorized}
          key.tenant.status != "active" -> {:error, :tenant_suspended}
          true -> {:ok, key}
        end
    end
  end

  defp credential?(value),
    do: is_binary(value) and value != "" and byte_size(value) <= @max_credential_bytes
end
