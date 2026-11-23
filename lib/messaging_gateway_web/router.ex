defmodule MessagingGatewayWeb.Router do
  use MessagingGatewayWeb, :router

  alias MessagingGatewayWeb.Plugs.AuthenticateApiKey

  pipeline :api do
    plug :accepts, ["json"]
    plug :put_api_headers
  end

  pipeline :api_key_auth do
    plug AuthenticateApiKey
  end

  scope "/api/v1", MessagingGatewayWeb do
    pipe_through [:api, :api_key_auth]

    post "/messages", MessageController, :create
    get "/messages/:id", MessageController, :show
  end

  defp put_api_headers(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
  end
end
