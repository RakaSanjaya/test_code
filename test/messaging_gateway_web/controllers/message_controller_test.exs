defmodule MessagingGatewayWeb.MessageControllerTest do
  use MessagingGatewayWeb.ConnCase, async: true

  alias MessagingGateway.Accounts.Tenant
  alias MessagingGateway.Messaging

  @iso ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/

  setup do
    a = tenant_fixture(%{balance: 10_000})
    ch_a = channel_fixture(a, %{default_category: "utility"})
    template_fixture(a, %{code: "otp_login_v1", category: "authentication"})
    b = tenant_fixture(%{balance: 10_000})

    %{
      a: a,
      b: b,
      ch_a: ch_a,
      ch_b: channel_fixture(b),
      a_full: api_key_fixture(a, ["messages:write", "messages:read"]),
      a_ro: api_key_fixture(a, ["messages:read"]),
      a_wo: api_key_fixture(a, ["messages:write"]),
      b_full: api_key_fixture(b, ["messages:write", "messages:read"])
    }
  end

  defp spec_body(ch) do
    %{
      "channel_id" => ch.id,
      "recipient" => "+6281234567890",
      "text" => "Kode OTP Anda adalah 849201",
      "template_code" => "otp_login_v1",
      "metadata" => %{"reference_id" => "order-123", "campaign" => "checkout"}
    }
  end

  test "POST happy path returns the spec shape", %{conn: conn, a_full: {k, s}, ch_a: ch} do
    conn = conn |> put_api_auth(k.client_key, s) |> post_json("/api/v1/messages", spec_body(ch))

    assert %{
             "data" =>
               %{
                 "id" => _,
                 "channel_id" => cid,
                 "recipient" => "+6281234567890",
                 "category" => "authentication",
                 "cost" => 300,
                 "status" => "queued",
                 "inserted_at" => ts
               } = d
           } = json_response(conn, 201)

    assert cid == ch.id and ts =~ @iso
    refute Map.has_key?(d, "content")
  end

  test "POST requires messages:write", %{conn: conn, a_ro: {k, s}, ch_a: ch} do
    conn = conn |> put_api_auth(k.client_key, s) |> post_json("/api/v1/messages", spec_body(ch))
    assert %{"error" => %{"code" => "insufficient_scope"}} = json_response(conn, 403)
  end

  test "POST without credentials is 401", %{conn: conn, ch_a: ch} do
    assert %{"error" => %{"code" => "unauthorized"}} =
             json_response(post_json(conn, "/api/v1/messages", spec_body(ch)), 401)
  end

  test "POST ignores tampering in body, metadata and query string",
       %{conn: conn, a_full: {k, s}, ch_a: ch, b: b} do
    evil = %{
      "category" => "authentication",
      "cost" => 1,
      "price" => 1,
      "status" => "delivered",
      "tenant_id" => b.id
    }

    body =
      Map.merge(
        %{
          "channel_id" => ch.id,
          "recipient" => "+6281234567890",
          "text" => "Halo",
          "metadata" => evil
        },
        evil
      )

    conn =
      conn
      |> put_api_auth(k.client_key, s)
      |> post_json("/api/v1/messages?category=authentication&cost=1", body)

    assert %{
             "data" => %{
               "category" => "utility",
               "cost" => 500,
               "status" => "queued",
               "metadata" => %{}
             }
           } = json_response(conn, 201)
  end

  test "POST with another tenant's channel is 422 channel_not_found",
       %{conn: conn, a_full: {k, s}, ch_b: ch_b} do
    conn =
      conn
      |> put_api_auth(k.client_key, s)
      |> post_json("/api/v1/messages", %{spec_body(ch_b) | "template_code" => nil})

    assert %{"error" => %{"code" => "channel_not_found"}} = json_response(conn, 422)
  end

  test "POST with insufficient balance is 402", %{conn: conn} do
    t = tenant_fixture(%{balance: 100})
    {k, s} = api_key_fixture(t)
    ch = channel_fixture(t)

    conn =
      conn
      |> put_api_auth(k.client_key, s)
      |> post_json("/api/v1/messages", %{
        "channel_id" => ch.id,
        "recipient" => "+6281234567890",
        "text" => "Halo"
      })

    assert json_response(conn, 402) == %{
             "error" => %{"code" => "insufficient_balance", "message" => "Insufficient balance"}
           }
  end

  test "Idempotency-Key replay returns the original with a marker header",
       %{a_full: {k, s}, ch_a: ch, a: a} do
    send = fn body ->
      build_conn()
      |> put_api_auth(k.client_key, s)
      |> put_req_header("idempotency-key", "order-123")
      |> post_json("/api/v1/messages", body)
    end

    first = send.(spec_body(ch))
    second = send.(spec_body(ch))
    assert json_response(first, 201)["data"]["id"] == json_response(second, 201)["data"]["id"]
    assert get_resp_header(second, "idempotent-replayed") == ["true"]
    assert get_resp_header(first, "idempotent-replayed") == []
    assert Repo.get!(Tenant, a.id).balance == 9_700

    assert %{"error" => %{"code" => "idempotency_key_reused"}} =
             json_response(send.(%{spec_body(ch) | "text" => "Kode OTP Anda adalah 1"}), 422)
  end

  test "duplicate Idempotency-Key headers are rejected", %{conn: conn, a_full: {k, s}, ch_a: ch} do
    conn =
      %{conn | req_headers: [{"idempotency-key", "a"}, {"idempotency-key", "b"}]}
      |> put_api_auth(k.client_key, s)
      |> post_json("/api/v1/messages", spec_body(ch))

    assert %{"error" => %{"code" => "invalid_idempotency_key"}} = json_response(conn, 422)
  end

  test "metadata [] is normalised to {}", %{conn: conn, a_full: {k, s}, ch_a: ch} do
    conn =
      conn
      |> put_api_auth(k.client_key, s)
      |> post_json("/api/v1/messages", %{spec_body(ch) | "metadata" => []})

    assert %{"data" => %{"metadata" => metadata}} = json_response(conn, 201)
    assert metadata == %{}
  end

  test "type confusion and non-object bodies are 422, never 500", %{a_full: {k, s}} do
    for body <- [
          %{
            "channel_id" => 123,
            "recipient" => "+6281234567890",
            "text" => ["a"],
            "metadata" => "x"
          },
          [1, 2],
          "\"str\""
        ] do
      conn = build_conn() |> put_api_auth(k.client_key, s) |> post_json("/api/v1/messages", body)

      assert %{"error" => %{"code" => "validation_failed", "details" => _}} =
               json_response(conn, 422)
    end
  end

  test "GET returns own message; foreign, missing and malformed ids are an identical 404", ctx do
    {k, s} = ctx.a_full

    {:ok, m, _} =
      Messaging.send_message(
        ctx.a,
        %{"channel_id" => ctx.ch_a.id, "recipient" => "+6281234567890", "text" => "Halo"},
        nil
      )

    own = build_conn() |> put_api_auth(k.client_key, s) |> get("/api/v1/messages/#{m.id}")
    assert %{"data" => %{"id" => id, "status" => "queued"}} = json_response(own, 200)
    assert id == m.id

    {bk, bs} = ctx.b_full

    bodies =
      for path <- [
            "/api/v1/messages/#{m.id}",
            "/api/v1/messages/#{Ecto.UUID.generate()}",
            "/api/v1/messages/not-a-uuid",
            "/api/v1/messages/%27%20OR%201%3D1%20--"
          ] do
        json_response(build_conn() |> put_api_auth(bk.client_key, bs) |> get(path), 404)
      end

    assert Enum.uniq(bodies) == [
             %{"error" => %{"code" => "not_found", "message" => "Message not found"}}
           ]
  end

  test "GET requires messages:read and sets no-store headers",
       %{a_wo: {k, s}, a_full: {fk, fs}} do
    assert %{"error" => %{"code" => "insufficient_scope"}} =
             json_response(
               build_conn()
               |> put_api_auth(k.client_key, s)
               |> get("/api/v1/messages/#{Ecto.UUID.generate()}"),
               403
             )

    conn =
      build_conn()
      |> put_api_auth(fk.client_key, fs)
      |> get("/api/v1/messages/#{Ecto.UUID.generate()}")

    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end
end
