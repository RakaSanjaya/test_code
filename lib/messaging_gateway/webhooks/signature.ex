defmodule MessagingGateway.Webhooks.Signature do
  @moduledoc """
  Vendor webhook signatures:

      X-Webhook-Signature: sha256=<hex(HMAC-SHA256(secret, "<timestamp>.<raw body>"))>

  The HMAC is computed over the exact bytes received (never re-encoded JSON),
  the timestamp must be within the tolerance window (replay protection), header
  formats are parsed strictly and the final comparison is constant-time.
  """

  @timestamp_format ~r/\A\d{1,12}\z/
  @signature_format ~r/\Asha256=[0-9a-f]{64}\z/

  @type error :: :missing_headers | :invalid_timestamp | :stale_timestamp | :invalid_signature

  @spec sign(String.t(), integer() | String.t(), binary()) :: String.t()
  def sign(secret, timestamp, raw_body) do
    mac = :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{raw_body}")
    "sha256=" <> Base.encode16(mac, case: :lower)
  end

  @spec verify(binary(), String.t() | nil, String.t() | nil, keyword()) :: :ok | {:error, error()}
  def verify(raw_body, timestamp_header, signature_header, opts) do
    secret = Keyword.fetch!(opts, :secret)
    now = Keyword.fetch!(opts, :now)
    tolerance = Keyword.fetch!(opts, :tolerance)

    with :ok <- present(timestamp_header, signature_header),
         {:ok, ts} <- parse_timestamp(timestamp_header),
         :ok <- within_window(ts, now, tolerance),
         :ok <- well_formed(signature_header) do
      if Plug.Crypto.secure_compare(sign(secret, timestamp_header, raw_body), signature_header),
        do: :ok,
        else: {:error, :invalid_signature}
    end
  end

  defp present(ts, sig) when is_binary(ts) and is_binary(sig), do: :ok
  defp present(_, _), do: {:error, :missing_headers}

  defp parse_timestamp(header) do
    if Regex.match?(@timestamp_format, header),
      do: {:ok, String.to_integer(header)},
      else: {:error, :invalid_timestamp}
  end

  defp within_window(ts, now, tolerance) do
    if abs(now - ts) <= tolerance, do: :ok, else: {:error, :stale_timestamp}
  end

  defp well_formed(signature) do
    if Regex.match?(@signature_format, signature), do: :ok, else: {:error, :invalid_signature}
  end
end
