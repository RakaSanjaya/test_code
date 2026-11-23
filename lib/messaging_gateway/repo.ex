defmodule MessagingGateway.Repo do
  use Ecto.Repo,
    otp_app: :messaging_gateway,
    adapter: Ecto.Adapters.Postgres
end
