defmodule MessagingGatewayWeb.Plugs.RateLimit do
  @moduledoc """
  Per-API-key rate limit. Runs after authentication, so someone who only knows a
  public `client_key` cannot burn a tenant's quota.
  """

  @behaviour Plug

  alias MessagingGateway.RateLimiter
  alias MessagingGatewayWeb.ErrorResponse

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{assigns: %{current_api_key: api_key}} = conn, _opts) do
    config = Application.fetch_env!(:messaging_gateway, :rate_limit)

    case RateLimiter.hit({:api_key, api_key.id}, config[:limit], config[:window_ms]) do
      :ok ->
        conn

      {:error, :rate_limited, retry_after_ms} ->
        conn
        |> Plug.Conn.put_resp_header(
          "retry-after",
          Integer.to_string(ceil(retry_after_ms / 1000))
        )
        |> ErrorResponse.send_error(429, "rate_limited", "Too many requests")
    end
  end
end
