# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :messaging_gateway,
  ecto_repos: [MessagingGateway.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true]

# Configure the endpoint
config :messaging_gateway, MessagingGatewayWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: MessagingGatewayWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MessagingGateway.PubSub,
  live_view: [signing_salt: "Bq0qelxt"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :messaging_gateway, MessagingGateway.Repo,
  migration_primary_key: [type: :binary_id],
  migration_foreign_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime_usec],
  # Query logs can contain message content and recipients; dev re-enables them locally.
  log: false

config :messaging_gateway, Oban,
  repo: MessagingGateway.Repo,
  queues: [dispatch: 10],
  plugins: [{Oban.Plugins.Pruner, max_age: 86_400}]

config :messaging_gateway,
  webhook_tolerance_seconds: 300,
  rate_limit: [limit: 120, window_ms: 60_000],
  vendor: MessagingGateway.Vendor.Mock

# Never log credentials, message bodies, recipients or metadata.
config :phoenix, :filter_parameters, [
  "secret",
  "password",
  "token",
  "authorization",
  "text",
  "content",
  "recipient",
  "metadata"
]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
