defmodule MessagingGatewayWeb.Plugs.ApiHeaders do
  @moduledoc """
  Security headers for every response, including errors rendered before or
  outside the router (no route, parse errors): responses carry balances and
  message data, so they must never be cached or content-sniffed.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
  end
end
