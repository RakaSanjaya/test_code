defmodule MessagingGatewayWeb.EndpointTest do
  use MessagingGatewayWeb.ConnCase, async: true

  defp json(conn), do: put_req_header(conn, "content-type", "application/json")

  # Phoenix renders NoRouteError without re-raising it, so assert on the response itself.
  test "unknown route renders the JSON 404 envelope", %{conn: conn} do
    conn = get(conn, "/api/v1/nope")

    assert json_response(conn, 404) == %{
             "error" => %{"code" => "not_found", "message" => "Not Found"}
           }
  end

  test "malformed JSON is 400, not 500", %{conn: conn} do
    assert_error_sent 400, fn -> conn |> json() |> post("/api/v1/messages", "{bad") end
  end

  test "body over 64 KB is 413", %{conn: conn} do
    big = Jason.encode!(%{"text" => String.duplicate("a", 70_000)})
    assert_error_sent 413, fn -> conn |> json() |> post("/api/v1/messages", big) end
  end

  test "non-JSON content type is 415", %{conn: conn} do
    assert_error_sent 415, fn ->
      conn |> put_req_header("content-type", "text/plain") |> post("/api/v1/messages", "hi")
    end
  end
end
