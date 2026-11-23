defmodule MessagingGatewayWeb.MessageController do
  use MessagingGatewayWeb, :controller

  alias MessagingGateway.Messaging
  alias MessagingGatewayWeb.Plugs.RequireScope

  plug RequireScope, "messages:write" when action == :create
  plug RequireScope, "messages:read" when action == :show

  action_fallback MessagingGatewayWeb.FallbackController

  # Params are read from the JSON body only; query-string params are ignored.
  def create(conn, _params) do
    tenant = conn.assigns.current_tenant

    with {:ok, message, result} <-
           Messaging.send_message(tenant, conn.body_params, idempotency_key(conn)) do
      conn
      |> maybe_mark_replayed(result)
      |> put_status(:created)
      |> render(:show, message: message)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, message} <- Messaging.get_message(conn.assigns.current_tenant.id, id) do
      render(conn, :show, message: message)
    end
  end

  defp idempotency_key(conn) do
    case get_req_header(conn, "idempotency-key") do
      [] -> nil
      [key] -> key
      _many -> :invalid
    end
  end

  defp maybe_mark_replayed(conn, :replayed),
    do: put_resp_header(conn, "idempotent-replayed", "true")

  defp maybe_mark_replayed(conn, :created), do: conn
end
