defmodule MessagingGatewayWeb.Plugs.RequireScopeTest do
  use MessagingGatewayWeb.ConnCase, async: true

  alias MessagingGatewayWeb.Plugs.RequireScope

  test "missing scope -> 403 insufficient_scope; present scope passes" do
    {ro, _} = api_key_fixture(tenant_fixture(), ["messages:read"])

    conn =
      build_conn()
      |> assign(:current_api_key, ro)
      |> RequireScope.call(RequireScope.init("messages:write"))

    assert conn.halted and conn.status == 403

    assert Jason.decode!(conn.resp_body) == %{
             "error" => %{
               "code" => "insufficient_scope",
               "message" => "API key lacks required scope: messages:write"
             }
           }

    refute (build_conn()
            |> assign(:current_api_key, ro)
            |> RequireScope.call(RequireScope.init("messages:read"))).halted
  end
end
