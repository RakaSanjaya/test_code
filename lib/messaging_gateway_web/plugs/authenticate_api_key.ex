defmodule MessagingGatewayWeb.Plugs.AuthenticateApiKey do
  @moduledoc """
  Authenticates `X-Client-Key` + `Authorization: Bearer <secret>`.

  Each header must appear exactly once. All credential failures produce one
  identical 401 body so callers cannot tell which part was wrong. The secret is
  never logged.
  """

  @behaviour Plug

  require Logger

  alias MessagingGateway.Accounts
  alias MessagingGatewayWeb.ErrorResponse

  @bearer ~r/\Abearer +(\S{1,512})\s*\z/i

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    client_key = single_header(conn, "x-client-key")

    with {:ok, secret} <- bearer_secret(conn),
         {:ok, api_key} <- Accounts.authenticate(client_key, secret) do
      conn
      |> Plug.Conn.assign(:current_api_key, api_key)
      |> Plug.Conn.assign(:current_tenant, api_key.tenant)
    else
      {:error, :tenant_suspended} ->
        ErrorResponse.send_error(conn, 403, "tenant_suspended", "Tenant is suspended")

      _ ->
        Logger.warning(
          "api_key_auth_failed client_key_prefix=#{inspect(String.slice(client_key || "", 0, 8))}"
        )

        conn
        |> Plug.Conn.put_resp_header("www-authenticate", "Bearer")
        |> ErrorResponse.send_error(401, "unauthorized", "Invalid or missing API credentials")
    end
  end

  defp bearer_secret(conn) do
    with header when is_binary(header) <- single_header(conn, "authorization"),
         [_, secret] <- Regex.run(@bearer, header) do
      {:ok, secret}
    else
      _ -> :error
    end
  end

  defp single_header(conn, name) do
    case Plug.Conn.get_req_header(conn, name) do
      [value] -> value
      _ -> nil
    end
  end
end
