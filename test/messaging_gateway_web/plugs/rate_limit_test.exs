defmodule MessagingGatewayWeb.Plugs.RateLimitTest do
  # async: false because it changes application env.
  use MessagingGatewayWeb.ConnCase, async: false

  setup do
    old = Application.fetch_env!(:messaging_gateway, :rate_limit)
    Application.put_env(:messaging_gateway, :rate_limit, limit: 2, window_ms: 60_000)
    on_exit(fn -> Application.put_env(:messaging_gateway, :rate_limit, old) end)
  end

  test "third request in the window is 429 and other keys are unaffected" do
    t = tenant_fixture()
    {a, as} = api_key_fixture(t)
    {b, bs} = api_key_fixture(t)
    path = "/api/v1/messages/#{Ecto.UUID.generate()}"

    for _ <- 1..2,
        do:
          assert(
            build_conn() |> put_api_auth(a.client_key, as) |> get(path) |> Map.get(:status) ==
              404
          )

    conn = build_conn() |> put_api_auth(a.client_key, as) |> get(path)

    assert json_response(conn, 429) == %{
             "error" => %{"code" => "rate_limited", "message" => "Too many requests"}
           }

    assert [retry] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry) >= 1
    assert build_conn() |> put_api_auth(b.client_key, bs) |> get(path) |> Map.get(:status) == 404
  end

  test "unauthenticated requests are rejected before the limiter" do
    for _ <- 1..5,
        do:
          assert(
            build_conn() |> get("/api/v1/messages/#{Ecto.UUID.generate()}") |> Map.get(:status) ==
              401
          )
  end
end
