defmodule MessagingGatewayWeb.ErrorJSONTest do
  use MessagingGatewayWeb.ConnCase, async: true

  test "renders 404" do
    assert MessagingGatewayWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert MessagingGatewayWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
