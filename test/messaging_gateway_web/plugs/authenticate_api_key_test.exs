defmodule MessagingGatewayWeb.Plugs.AuthenticateApiKeyTest do
  use MessagingGatewayWeb.ConnCase, async: true

  alias MessagingGatewayWeb.Plugs.AuthenticateApiKey

  @unauthorized %{
    "error" => %{"code" => "unauthorized", "message" => "Invalid or missing API credentials"}
  }

  setup do
    t = tenant_fixture()
    {key, secret} = api_key_fixture(t)
    %{t: t, key: key, secret: secret}
  end

  defp run(conn), do: AuthenticateApiKey.call(conn, AuthenticateApiKey.init([]))

  test "valid credentials (including lowercase 'bearer') assign key and tenant", ctx do
    for scheme <- ["Bearer", "bearer"] do
      conn =
        build_conn()
        |> put_req_header("x-client-key", ctx.key.client_key)
        |> put_req_header("authorization", "#{scheme} #{ctx.secret}")
        |> run()

      refute conn.halted
      assert conn.assigns.current_tenant.id == ctx.t.id
      assert conn.assigns.current_api_key.id == ctx.key.id
    end
  end

  test "every credential failure returns the same 401 body", %{key: key, secret: s} do
    ok = put_api_auth(build_conn(), key.client_key, s)

    variants = [
      build_conn(),
      build_conn() |> put_req_header("x-client-key", key.client_key),
      build_conn() |> put_req_header("authorization", "Bearer " <> s),
      put_api_auth(build_conn(), key.client_key, "sk_wrong"),
      put_api_auth(build_conn(), "ck_unknown", s),
      build_conn()
      |> put_req_header("x-client-key", key.client_key)
      |> put_req_header("authorization", "Basic " <> s),
      build_conn()
      |> put_req_header("x-client-key", key.client_key)
      |> put_req_header("authorization", "Bearer "),
      put_api_auth(build_conn(), key.client_key, String.duplicate("a", 10_000)),
      %{ok | req_headers: [{"x-client-key", key.client_key} | ok.req_headers]}
    ]

    for conn <- Enum.map(variants, &run/1) do
      assert conn.halted and conn.status == 401
      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
      assert Jason.decode!(conn.resp_body) == @unauthorized
    end
  end

  test "suspended tenant gets 403 tenant_suspended" do
    {key, s} = api_key_fixture(tenant_fixture(%{status: "suspended"}))
    conn = build_conn() |> put_api_auth(key.client_key, s) |> run()
    assert conn.status == 403
    assert %{"error" => %{"code" => "tenant_suspended"}} = Jason.decode!(conn.resp_body)
  end
end
