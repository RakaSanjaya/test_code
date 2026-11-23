defmodule MessagingGatewayWeb.WebhookControllerTest do
  use MessagingGatewayWeb.ConnCase, async: true

  alias MessagingGateway.Accounts.Tenant
  alias MessagingGateway.Billing.BalanceTransaction
  alias MessagingGateway.Messaging
  alias MessagingGateway.Messaging.Message
  alias MessagingGateway.Webhooks.Signature

  import Ecto.Query

  @rejected %{
    "error" => %{
      "code" => "invalid_signature",
      "message" => "Webhook signature verification failed"
    }
  }

  setup do
    t = tenant_fixture(%{balance: 10_000})
    ch = channel_fixture(t)

    {:ok, m, _} =
      Messaging.send_message(
        t,
        %{"channel_id" => ch.id, "recipient" => "+6281234567890", "text" => "Halo"},
        nil
      )

    %{t: t, m: m}
  end

  defp dlr(id, status, extra \\ %{}),
    do: Jason.encode!(Map.merge(%{"message_id" => id, "status" => status}, extra))

  defp refunds(m) do
    Repo.aggregate(
      from(x in BalanceTransaction, where: x.message_id == ^m.id and x.type == "refund"),
      :count
    )
  end

  test "valid signed report moves queued -> sent", %{conn: conn, m: m} do
    conn = signed_webhook_post(conn, dlr(m.id, "sent"))

    assert json_response(conn, 200) == %{
             "data" => %{"message_id" => m.id, "status" => "sent", "result" => "updated"}
           }
  end

  test "failed refunds once even when the vendor retries the same delivery", %{t: t, m: m} do
    raw = dlr(m.id, "failed", %{"reason" => "recipient_unreachable"})
    ts = System.system_time(:second)

    assert %{"data" => %{"result" => "updated"}} =
             json_response(signed_webhook_post(build_conn(), raw, timestamp: ts), 200)

    assert %{"data" => %{"result" => "unchanged"}} =
             json_response(signed_webhook_post(build_conn(), raw, timestamp: ts), 200)

    assert Repo.get!(Tenant, t.id).balance == 10_000
    assert refunds(m) == 1
  end

  test "signature is checked against the raw bytes, not re-encoded JSON", %{conn: conn, m: m} do
    raw = ~s({  "status" : "sent",\n  "message_id" : "#{m.id}"  })
    assert json_response(signed_webhook_post(conn, raw), 200)
  end

  test "bad signature, tampered body, stale or future timestamp, missing headers -> 401, nothing changes",
       %{m: m} do
    raw = dlr(m.id, "failed")
    now = System.system_time(:second)

    rejected = [
      signed_webhook_post(build_conn(), raw, signature: "sha256=" <> String.duplicate("0", 64)),
      signed_webhook_post(build_conn(), raw, secret: "wrong-secret"),
      signed_webhook_post(build_conn(), dlr(m.id, "failed", %{"x" => 1}),
        signature: Signature.sign(webhook_secret(), now, raw),
        timestamp: now
      ),
      signed_webhook_post(build_conn(), raw, timestamp: now - 301),
      signed_webhook_post(build_conn(), raw, timestamp: now + 301),
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/webhooks/vendor", raw)
    ]

    for conn <- rejected, do: assert(json_response(conn, 401) == @rejected)
    assert Repo.get!(Message, m.id).status == "queued" and refunds(m) == 0
  end

  test "timestamp inside the window is accepted", %{conn: conn, m: m} do
    assert json_response(
             signed_webhook_post(conn, dlr(m.id, "sent"),
               timestamp: System.system_time(:second) - 290
             ),
             200
           )
  end

  test "signed but invalid payloads are 422", %{m: m} do
    for raw <- [
          dlr(m.id, "read"),
          dlr(m.id, "queued"),
          dlr("not-a-uuid", "sent"),
          dlr(m.id, "failed", %{"reason" => String.duplicate("r", 256)}),
          "[1, 2]"
        ] do
      assert %{"error" => %{"code" => "validation_failed"}} =
               json_response(signed_webhook_post(build_conn(), raw), 422)
    end
  end

  test "unknown message is 404; illegal transition is 409 without refund", %{m: m} do
    assert %{"error" => %{"code" => "not_found"}} =
             json_response(
               signed_webhook_post(build_conn(), dlr(Ecto.UUID.generate(), "sent")),
               404
             )

    assert %{"error" => %{"code" => "invalid_transition"}} =
             json_response(signed_webhook_post(build_conn(), dlr(m.id, "delivered")), 409)

    json_response(signed_webhook_post(build_conn(), dlr(m.id, "sent")), 200)
    json_response(signed_webhook_post(build_conn(), dlr(m.id, "delivered")), 200)

    assert %{"error" => %{"code" => "invalid_transition"}} =
             json_response(signed_webhook_post(build_conn(), dlr(m.id, "failed")), 409)

    assert refunds(m) == 0
  end

  test "non-JSON content type is 415", %{conn: conn, m: m} do
    assert_error_sent 415, fn ->
      signed_webhook_post(conn, dlr(m.id, "sent"), content_type: "text/plain")
    end
  end
end
