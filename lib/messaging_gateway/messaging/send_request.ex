defmodule MessagingGateway.Messaging.SendRequest do
  @moduledoc """
  The trust boundary for `POST /api/v1/messages`.

  Only `channel_id`, `recipient`, `text`, `template_code` and `metadata` are ever
  read from the client. Billing/ownership fields (`category`, `cost`, `price`,
  `status`, `tenant_id`, ...) are not part of the schema, so they are dropped at
  the root, and reserved keys are stripped from `metadata` as well. Metadata is
  stored for the client's reference only and is never consulted by pricing.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :channel_id, Ecto.UUID
    field :recipient, :string
    field :text, :string
    field :template_code, :string
    field :metadata, :map, default: %{}
  end

  @type t :: %__MODULE__{}

  @reserved_metadata_keys ~w(tenant_id cost price category status channel_id id)
  @max_metadata_keys 20
  @max_metadata_key_length 40
  @max_metadata_value_length 500
  @max_text_length 4096

  @recipient_format ~r/\A\+[1-9]\d{7,14}\z/
  @template_code_format ~r/\A[a-z0-9_]{1,64}\z/
  @idempotency_key_format ~r/\A[\x21-\x7E]{1,255}\z/

  def reserved_metadata_keys, do: @reserved_metadata_keys

  @spec validate(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def validate(params) when is_map(params) do
    params = Map.put(params, "metadata", normalize_metadata(Map.get(params, "metadata")))

    %__MODULE__{}
    |> cast(params, [:channel_id, :recipient, :text, :template_code, :metadata])
    |> validate_required([:channel_id, :recipient, :text])
    |> validate_format(:recipient, @recipient_format,
      message: "must be E.164, e.g. +6281234567890"
    )
    |> validate_length(:text, min: 1, max: @max_text_length)
    |> validate_change(:text, &reject_nul/2)
    |> validate_format(:template_code, @template_code_format)
    |> validate_change(:metadata, &validate_metadata/2)
    |> apply_action(:validate)
  end

  def validate(_params), do: validate(%{})

  @spec validate_idempotency_key(term()) ::
          {:ok, String.t() | nil} | {:error, :invalid_idempotency_key}
  def validate_idempotency_key(nil), do: {:ok, nil}

  def validate_idempotency_key(key) when is_binary(key) do
    if Regex.match?(@idempotency_key_format, key),
      do: {:ok, key},
      else: {:error, :invalid_idempotency_key}
  end

  def validate_idempotency_key(_), do: {:error, :invalid_idempotency_key}

  @doc "Deterministic SHA-256 of the normalised request, used to detect Idempotency-Key reuse."
  @spec fingerprint(t()) :: String.t()
  def fingerprint(%__MODULE__{} = req) do
    term = {req.channel_id, req.recipient, req.text, req.template_code, req.metadata}

    :sha256
    |> :crypto.hash(:erlang.term_to_binary(term, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  # PHP/legacy clients send `[]` for an empty object.
  defp normalize_metadata(nil), do: %{}
  defp normalize_metadata([]), do: %{}

  defp normalize_metadata(%{} = metadata) do
    Map.reject(metadata, fn {key, _} ->
      is_binary(key) and String.downcase(key) in @reserved_metadata_keys
    end)
  end

  defp normalize_metadata(other), do: other

  defp validate_metadata(:metadata, metadata) do
    cond do
      map_size(metadata) > @max_metadata_keys ->
        [metadata: "must have at most #{@max_metadata_keys} keys"]

      not Enum.all?(metadata, &valid_metadata_entry?/1) ->
        [
          metadata:
            "must be a flat object: keys of 1-#{@max_metadata_key_length} characters, " <>
              "values that are strings (max #{@max_metadata_value_length}), numbers, booleans or null"
        ]

      true ->
        []
    end
  end

  defp valid_metadata_entry?({key, value}) do
    is_binary(key) and String.length(key) in 1..@max_metadata_key_length and not nul?(key) and
      valid_metadata_value?(value)
  end

  defp valid_metadata_value?(value) when is_binary(value),
    do: String.length(value) <= @max_metadata_value_length and not nul?(value)

  defp valid_metadata_value?(value), do: is_number(value) or is_boolean(value) or is_nil(value)

  # PostgreSQL text and jsonb cannot store U+0000; reject it here instead of crashing in the DB.
  defp reject_nul(field, value),
    do: if(nul?(value), do: [{field, "must not contain NUL"}], else: [])

  defp nul?(value), do: String.contains?(value, <<0>>)
end
