defmodule MessagingGatewayWeb.FallbackController do
  @moduledoc "Maps domain errors to HTTP responses in the standard error envelope."
  use MessagingGatewayWeb, :controller

  alias MessagingGatewayWeb.ErrorResponse

  @errors %{
    invalid_idempotency_key:
      {422, "invalid_idempotency_key", "Idempotency-Key must be 1-255 printable ASCII characters"},
    idempotency_key_reused:
      {422, "idempotency_key_reused",
       "Idempotency-Key was already used with a different request body"},
    channel_not_found: {422, "channel_not_found", "Channel not found"},
    channel_inactive: {422, "channel_inactive", "Channel is inactive"},
    template_not_found: {422, "template_not_found", "Template not found"},
    template_not_approved: {422, "template_not_approved", "Template is not approved"},
    template_mismatch: {422, "template_mismatch", "Text does not match the template body"},
    insufficient_balance: {402, "insufficient_balance", "Insufficient balance"},
    tenant_suspended: {403, "tenant_suspended", "Tenant is suspended"},
    not_found: {404, "not_found", "Message not found"},
    invalid_status: {422, "invalid_status", "Unsupported status"},
    invalid_transition: {409, "invalid_transition", "Status transition is not allowed"}
  }

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    ErrorResponse.send_error(
      conn,
      422,
      "validation_failed",
      "Request validation failed",
      Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
    )
  end

  def call(conn, {:error, reason}) when is_map_key(@errors, reason) do
    {status, code, message} = Map.fetch!(@errors, reason)
    ErrorResponse.send_error(conn, status, code, message)
  end

  # Interpolates from the (atom-keyed) opts we already have; never converts input to atoms.
  defp translate_error({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> interpolation(value) end)
    end)
  end

  defp interpolation(value) when is_binary(value) or is_number(value) or is_atom(value),
    do: to_string(value)

  defp interpolation(value), do: inspect(value)
end
