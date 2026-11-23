defmodule MessagingGatewayWeb.Router do
  use MessagingGatewayWeb, :router

  alias MessagingGatewayWeb.Plugs.{AuthenticateApiKey, RateLimit, VerifyWebhookSignature}

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_key_auth do
    plug AuthenticateApiKey
    plug RateLimit
  end

  pipeline :vendor_webhook do
    plug VerifyWebhookSignature
  end

  scope "/api/v1/webhooks", MessagingGatewayWeb do
    pipe_through [:api, :vendor_webhook]

    post "/vendor", WebhookController, :vendor
  end

  scope "/api/v1", MessagingGatewayWeb do
    pipe_through [:api, :api_key_auth]

    post "/messages", MessageController, :create
    get "/messages/:id", MessageController, :show
  end
end
