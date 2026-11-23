defmodule MessagingGateway.Webhooks.SignatureTest do
  use ExUnit.Case, async: true

  alias MessagingGateway.Webhooks.Signature

  # Reference vectors computed with:
  #   printf '%s.%s' "$TS" "$BODY" | openssl dgst -sha256 -hmac "$SECRET"
  @secret "whsec_test_vector"
  @ts 1_700_000_000
  @body ~s({"message_id":"9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d","status":"failed","reason":"recipient_unreachable"})
  @opts [secret: @secret, now: @ts, tolerance: 300]

  test "sign/3 matches reference HMAC-SHA256 vectors" do
    assert Signature.sign(@secret, @ts, @body) ==
             "sha256=fb8eb0716c69a7ee14c7832a82c61762ceb7e6558bbf20bbd44c546427dcce4a"

    assert Signature.sign(@secret, @ts, "") ==
             "sha256=5d214ab8aae77534faddd1185d69bf8cc2e74a38a53fcac06058e79a7ebed96f"
  end

  test "verify/4 accepts the window boundary and rejects outside it" do
    sig = fn ts -> Signature.sign(@secret, ts, @body) end
    assert :ok = Signature.verify(@body, "#{@ts - 300}", sig.(@ts - 300), @opts)
    assert :ok = Signature.verify(@body, "#{@ts + 300}", sig.(@ts + 300), @opts)

    assert {:error, :stale_timestamp} =
             Signature.verify(@body, "#{@ts - 301}", sig.(@ts - 301), @opts)

    assert {:error, :stale_timestamp} =
             Signature.verify(@body, "#{@ts + 301}", sig.(@ts + 301), @opts)
  end

  test "verify/4 rejects malformed input" do
    good = Signature.sign(@secret, @ts, @body)
    assert {:error, :missing_headers} = Signature.verify(@body, nil, good, @opts)
    assert {:error, :missing_headers} = Signature.verify(@body, "#{@ts}", nil, @opts)

    for ts <- ["abc", "-5", "1e9", "1700000000.0", String.duplicate("1", 13), " 1700000000"],
        do: assert({:error, :invalid_timestamp} = Signature.verify(@body, ts, good, @opts))

    "sha256=" <> hex = good

    for s <- [
          hex,
          "sha256=" <> String.upcase(hex),
          "sha1=" <> hex,
          "sha256=" <> String.slice(hex, 0, 63),
          good <> "0"
        ],
        do: assert({:error, :invalid_signature} = Signature.verify(@body, "#{@ts}", s, @opts))

    assert {:error, :invalid_signature} = Signature.verify(@body <> " ", "#{@ts}", good, @opts)

    assert {:error, :invalid_signature} =
             Signature.verify(@body, "#{@ts}", Signature.sign("other", @ts, @body), @opts)
  end
end
