defmodule MessagingGatewayWeb.Router do
  use MessagingGatewayWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MessagingGatewayWeb do
    pipe_through :api
  end
end
