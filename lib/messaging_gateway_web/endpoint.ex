defmodule MessagingGatewayWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :messaging_gateway

  # Server-to-server JSON API: no sessions, no static files, no method override.

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :messaging_gateway
  end

  plug MessagingGatewayWeb.Plugs.ApiHeaders
  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:json],
    pass: [],
    json_decoder: Phoenix.json_library(),
    length: 65_536,
    body_reader: {MessagingGatewayWeb.Plugs.CacheRawBody, :read_body, []}

  plug Plug.Head
  plug MessagingGatewayWeb.Router
end
