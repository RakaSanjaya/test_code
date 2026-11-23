defmodule MessagingGatewayWeb.LogHygieneTest do
  # async: false because it raises the global Logger level.
  use MessagingGatewayWeb.ConnCase, async: false

  setup do
    old = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: old) end)
  end

  test "Phoenix parameter filtering redacts sensitive fields" do
    out =
      Phoenix.Logger.filter_values(%{
        "text" => "849201",
        "recipient" => "+62",
        "metadata" => %{"a" => 1},
        "channel_id" => "c"
      })

    assert out == %{
             "text" => "[FILTERED]",
             "recipient" => "[FILTERED]",
             "metadata" => "[FILTERED]",
             "channel_id" => "c"
           }
  end

  test "no secret, OTP, recipient or webhook secret reaches the log, even at debug level" do
    t = tenant_fixture()
    {k, s} = api_key_fixture(t)
    ch = channel_fixture(t)
    template_fixture(t)

    log =
      ExUnit.CaptureLog.capture_log([level: :debug], fn ->
        conn =
          build_conn()
          |> put_api_auth(k.client_key, s)
          |> post_json("/api/v1/messages", %{
            "channel_id" => ch.id,
            "recipient" => "+6281234567890",
            "text" => "Kode OTP Anda adalah 849201",
            "template_code" => "otp_login_v1"
          })

        id = json_response(conn, 201)["data"]["id"]

        build_conn()
        |> put_api_auth(k.client_key, "sk_wrong_but_looks_real_000000000000")
        |> get("/api/v1/messages/#{id}")

        signed_webhook_post(
          build_conn(),
          Jason.encode!(%{"message_id" => id, "status" => "failed", "reason" => "x"})
        )

        signed_webhook_post(build_conn(), "{}", signature: "sha256=" <> String.duplicate("0", 64))
      end)

    assert log =~ "POST /api/v1/messages"

    for secret <- [
          s,
          "849201",
          "+6281234567890",
          "sk_wrong_but_looks_real_000000000000",
          webhook_secret()
        ],
        do: refute(log =~ secret)
  end
end
