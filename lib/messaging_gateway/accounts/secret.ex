defmodule MessagingGateway.Accounts.Secret do
  @moduledoc """
  API key material.

  Secrets are 256-bit CSPRNG values, so a fast keyed hash is sufficient: we store
  `HMAC-SHA256(pepper, secret)` (pepper lives in the environment, not the DB) and
  compare in constant time. A slow password hash would add nothing against brute
  force at this entropy and would turn every request into a CPU DoS vector.
  """

  @dummy_hash String.duplicate("0", 64)

  @spec generate_client_key() :: String.t()
  def generate_client_key, do: "ck_" <> random(18)

  @spec generate_secret() :: String.t()
  def generate_secret, do: "sk_" <> random(32)

  @spec hash(String.t(), String.t()) :: String.t()
  def hash(secret, pepper \\ pepper()) when is_binary(secret) and is_binary(pepper) do
    :hmac |> :crypto.mac(:sha256, pepper, secret) |> Base.encode16(case: :lower)
  end

  @spec verify(String.t(), String.t()) :: boolean()
  def verify(secret, stored_hash) when is_binary(secret) and is_binary(stored_hash) do
    Plug.Crypto.secure_compare(hash(secret), stored_hash)
  end

  def verify(_, _), do: false

  @doc "Performs the same work as `verify/2` for unknown client keys, then fails."
  @spec dummy_verify(term()) :: false
  def dummy_verify(secret) do
    _ = Plug.Crypto.secure_compare(hash(if(is_binary(secret), do: secret, else: "")), @dummy_hash)
    false
  end

  defp random(bytes),
    do: bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp pepper, do: Application.fetch_env!(:messaging_gateway, :api_key_pepper)
end
