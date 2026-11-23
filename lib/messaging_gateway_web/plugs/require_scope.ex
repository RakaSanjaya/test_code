defmodule MessagingGatewayWeb.Plugs.RequireScope do
  @moduledoc "Halts with 403 unless the authenticated API key carries the given scope."

  @behaviour Plug

  alias MessagingGateway.Accounts.ApiKey
  alias MessagingGatewayWeb.ErrorResponse

  @impl true
  def init(scope) when is_binary(scope), do: scope

  @impl true
  def call(conn, scope) do
    case conn.assigns do
      %{current_api_key: %ApiKey{} = key} ->
        if ApiKey.has_scope?(key, scope), do: conn, else: deny(conn, scope)

      _ ->
        deny(conn, scope)
    end
  end

  defp deny(conn, scope) do
    ErrorResponse.send_error(
      conn,
      403,
      "insufficient_scope",
      "API key lacks required scope: #{scope}"
    )
  end
end
