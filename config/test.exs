import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :messaging_gateway, MessagingGateway.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: String.to_integer(System.get_env("DB_PORT", "55432")),
  database: "messaging_gateway_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 30

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :messaging_gateway, MessagingGatewayWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Q9seyk55i6Fy+TvAG+v2R5gBNIrbv3VwnYvaGED6Rl1oTjtyPW6FDr+5I7csHFlb",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :messaging_gateway, Oban, testing: :manual

config :messaging_gateway,
  webhook_secret: "test_webhook_secret_0123456789abcdef0123",
  api_key_pepper: "test_api_key_pepper_0123456789abcdef0123",
  rate_limit: [limit: 10_000, window_ms: 60_000]
