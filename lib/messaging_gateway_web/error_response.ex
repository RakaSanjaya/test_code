defmodule MessagingGatewayWeb.ErrorResponse do
  @moduledoc """
  Sends the API error envelope from plugs and halts:
  `{"error": {"code": "...", "message": "...", "details": {...}}}` (`details` optional).
  """

  import Plug.Conn

  @spec send_error(Plug.Conn.t(), pos_integer(), String.t(), String.t(), map() | nil) ::
          Plug.Conn.t()
  def send_error(conn, status, code, message, details \\ nil) do
    error = %{code: code, message: message}
    error = if details, do: Map.put(error, :details, details), else: error

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: error}))
    |> halt()
  end
end
