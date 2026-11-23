defmodule MessagingGateway.Messaging.SendRequestTest do
  use ExUnit.Case, async: true

  alias MessagingGateway.Messaging.SendRequest

  @channel_id "550e8400-e29b-41d4-a716-446655440000"
  @valid %{
    "channel_id" => @channel_id,
    "recipient" => "+6281234567890",
    "text" => "Kode OTP Anda adalah 849201",
    "template_code" => "otp_login_v1",
    "metadata" => %{"reference_id" => "order-123", "campaign" => "checkout"}
  }

  defp error_fields(params) do
    {:error, cs} = SendRequest.validate(params)
    Keyword.keys(cs.errors)
  end

  test "accepts the spec example" do
    assert {:ok,
            %SendRequest{
              channel_id: @channel_id,
              recipient: "+6281234567890",
              template_code: "otp_login_v1",
              metadata: %{"reference_id" => "order-123", "campaign" => "checkout"}
            }} = SendRequest.validate(@valid)
  end

  test "billing and ownership fields at the root are never accepted" do
    tampered =
      Map.merge(@valid, %{
        "category" => "authentication",
        "cost" => 1,
        "price" => 0,
        "status" => "delivered",
        "tenant_id" => Ecto.UUID.generate()
      })

    {:ok, req} = SendRequest.validate(tampered)

    assert req |> Map.from_struct() |> Map.keys() |> Enum.sort() ==
             [:channel_id, :metadata, :recipient, :template_code, :text]
  end

  test "reserved metadata keys are stripped case-insensitively" do
    md = %{
      "cost" => 0,
      "Category" => "authentication",
      "TENANT_ID" => "x",
      "price" => 1,
      "status" => "sent",
      "id" => "x",
      "channel_id" => "x",
      "reference_id" => "r"
    }

    assert {:ok, %{metadata: %{"reference_id" => "r"} = m}} =
             SendRequest.validate(%{@valid | "metadata" => md})

    assert map_size(m) == 1
  end

  test "metadata [] / nil / missing normalise to %{}" do
    for p <- [
          %{@valid | "metadata" => []},
          %{@valid | "metadata" => nil},
          Map.delete(@valid, "metadata")
        ] do
      assert {:ok, %{metadata: m}} = SendRequest.validate(p)
      assert m == %{}
    end
  end

  test "invalid metadata shapes are rejected" do
    bad = [
      "x",
      ["a"],
      %{"a" => %{"b" => 1}},
      %{"a" => [1]},
      Map.new(1..21, &{"k#{&1}", 1}),
      %{String.duplicate("k", 41) => 1},
      %{"k" => String.duplicate("v", 501)}
    ]

    for m <- bad, do: assert(:metadata in error_fields(%{@valid | "metadata" => m}))
  end

  test "recipient must be strict E.164" do
    for r <- [
          "081234567890",
          "+0812345678",
          "+62812345678901234",
          "+6281234567890\n",
          "+62 812 3456",
          6_281_234_567_890
        ],
        do: assert(:recipient in error_fields(%{@valid | "recipient" => r}))
  end

  test "text is required and bounded to 4096 characters" do
    for t <- [nil, "", String.duplicate("a", 4097), ["a"]],
        do: assert(:text in error_fields(%{@valid | "text" => t}))

    assert {:ok, _} = SendRequest.validate(%{@valid | "text" => String.duplicate("😀", 4096)})
  end

  # PostgreSQL rejects NUL in text and jsonb; it must be a 422, never a DB exception.
  test "NUL characters are rejected in text and metadata" do
    assert :text in error_fields(%{@valid | "text" => "a\u0000b"})
    assert :metadata in error_fields(%{@valid | "metadata" => %{"k" => "a\u0000"}})
    assert :metadata in error_fields(%{@valid | "metadata" => %{"k\u0000" => 1}})
  end

  test "channel_id must be a UUID" do
    for c <- ["not-a-uuid", 123, nil],
        do: assert(:channel_id in error_fields(%{@valid | "channel_id" => c}))
  end

  test "template_code format; absent means nil" do
    for c <- ["../etc", "OTP", String.duplicate("a", 65), "otp\n"],
        do: assert(:template_code in error_fields(%{@valid | "template_code" => c}))

    assert {:ok, %{template_code: nil}} =
             SendRequest.validate(Map.delete(@valid, "template_code"))
  end

  test "non-object JSON body (wrapped by Plug as _json) fails cleanly" do
    assert [:channel_id, :recipient, :text] -- error_fields(%{"_json" => [1, 2]}) == []
  end

  test "validate_idempotency_key/1" do
    assert SendRequest.validate_idempotency_key(nil) == {:ok, nil}
    assert SendRequest.validate_idempotency_key("order-123:retry_1") == {:ok, "order-123:retry_1"}
    assert {:ok, _} = SendRequest.validate_idempotency_key(String.duplicate("a", 255))

    for k <- ["", String.duplicate("a", 256), "has space", "ключ", "a\n", 123],
        do: assert(SendRequest.validate_idempotency_key(k) == {:error, :invalid_idempotency_key})
  end

  test "fingerprint/1 is stable, order-insensitive for metadata, and content-sensitive" do
    {:ok, a} = SendRequest.validate(%{@valid | "metadata" => Map.new([{"x", 1}, {"y", 2}])})
    {:ok, b} = SendRequest.validate(%{@valid | "metadata" => Map.new([{"y", 2}, {"x", 1}])})
    {:ok, c} = SendRequest.validate(%{@valid | "text" => "Kode OTP Anda adalah 111111"})
    assert SendRequest.fingerprint(a) == SendRequest.fingerprint(b)
    refute SendRequest.fingerprint(a) == SendRequest.fingerprint(c)
    assert SendRequest.fingerprint(a) =~ ~r/\A[0-9a-f]{64}\z/
  end
end
