defmodule MessagingGatewayWeb.Plugs.CacheRawBody do
  @moduledoc """
  `Plug.Parsers` body reader that keeps the exact request bytes for the vendor
  webhook path only, so the HMAC can be verified over the raw body. Other paths
  are not buffered twice.
  """

  @webhook_path ["api", "v1", "webhooks", "vendor"]

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, chunk, conn} -> {:ok, chunk, cache(conn, chunk)}
      {:more, chunk, conn} -> {:more, chunk, cache(conn, chunk)}
      {:error, _} = error -> error
    end
  end

  @spec raw_body(Plug.Conn.t()) :: binary()
  def raw_body(conn), do: IO.iodata_to_binary(conn.private[:raw_body] || "")

  defp cache(%Plug.Conn{path_info: @webhook_path} = conn, chunk) do
    Plug.Conn.put_private(conn, :raw_body, [conn.private[:raw_body] || "", chunk])
  end

  defp cache(conn, _chunk), do: conn
end
