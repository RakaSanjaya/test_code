defmodule MessagingGatewayWeb.Plugs.VerifyWebhookSignature do
  @moduledoc """
  Rejects vendor webhooks whose `X-Webhook-Signature` / `X-Webhook-Timestamp`
  do not verify over the raw request body. Every failure returns the same 401;
  the specific reason is only logged.
  """

  @behaviour Plug

  require Logger

  alias MessagingGateway.Webhooks.Signature
  alias MessagingGatewayWeb.ErrorResponse
  alias MessagingGatewayWeb.Plugs.CacheRawBody

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    opts = [
      secret: Application.fetch_env!(:messaging_gateway, :webhook_secret),
      now: System.system_time(:second),
      tolerance: Application.fetch_env!(:messaging_gateway, :webhook_tolerance_seconds)
    ]

    result =
      Signature.verify(
        CacheRawBody.raw_body(conn),
        single_header(conn, "x-webhook-timestamp"),
        single_header(conn, "x-webhook-signature"),
        opts
      )

    case result do
      :ok ->
        conn

      {:error, reason} ->
        Logger.warning("webhook_signature_rejected reason=#{reason}")

        ErrorResponse.send_error(
          conn,
          401,
          "invalid_signature",
          "Webhook signature verification failed"
        )
    end
  end

  defp single_header(conn, name) do
    case Plug.Conn.get_req_header(conn, name) do
      [value] -> value
      _ -> nil
    end
  end
end
