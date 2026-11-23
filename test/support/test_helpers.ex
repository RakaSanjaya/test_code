defmodule MessagingGatewayWeb.TestHelpers do
  @moduledoc """
  HTTP helpers shared by ConnCase tests and the (non-ConnCase) concurrency suite.
  """

  import Plug.Conn

  @doc "Adds `x-client-key` and `authorization: Bearer <secret>`."
  def put_api_auth(conn, client_key, secret) do
    conn
    |> put_req_header("x-client-key", client_key)
    |> put_req_header("authorization", "Bearer " <> secret)
  end

  def webhook_secret, do: Application.fetch_env!(:messaging_gateway, :webhook_secret)

  @doc """
  POSTs `raw_body` to the vendor webhook, signed like the vendor would.

  Options: `:timestamp` (default now), `:secret` (default config), `:signature`
  (override the computed header), `:content_type` (default application/json).
  """
  def signed_webhook_post(conn, raw_body, opts \\ []) do
    ts = Keyword.get_lazy(opts, :timestamp, fn -> System.system_time(:second) end)
    secret = Keyword.get_lazy(opts, :secret, &webhook_secret/0)

    signature =
      Keyword.get_lazy(opts, :signature, fn ->
        MessagingGateway.Webhooks.Signature.sign(secret, ts, raw_body)
      end)

    conn
    |> put_req_header("content-type", Keyword.get(opts, :content_type, "application/json"))
    |> put_req_header("x-webhook-timestamp", to_string(ts))
    |> put_req_header("x-webhook-signature", signature)
    |> Phoenix.ConnTest.dispatch(
      MessagingGatewayWeb.Endpoint,
      :post,
      "/api/v1/webhooks/vendor",
      raw_body
    )
  end

  @doc "POSTs JSON. Maps/lists are encoded; binaries are sent byte-for-byte."
  def post_json(conn, path, body) do
    raw = if is_binary(body), do: body, else: Jason.encode!(body)

    conn
    |> put_req_header("content-type", "application/json")
    |> Phoenix.ConnTest.dispatch(MessagingGatewayWeb.Endpoint, :post, path, raw)
  end
end
