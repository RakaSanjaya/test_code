defmodule MessagingGatewayWeb.TestHelpers do
  @moduledoc """
  HTTP helpers shared by ConnCase tests and the (non-ConnCase) concurrency suite.
  """

  import Plug.Conn

  @doc "Adds `x-client-key` and `authorization: Bearer <secret>`."
  def put_api_auth(conn, client_key, secret) do
    conn
    |> put_req_header("x-client-key", client_key)
    |> put_req_header("authorization", "Bearer " <> secret)
  end
end
