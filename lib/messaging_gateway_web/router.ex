defmodule MessagingGatewayWeb.Router do
  use MessagingGatewayWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug :put_api_headers
  end

  defp put_api_headers(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
  end
end
