defmodule MessagingGateway.Webhooks.DeliveryReportTest do
  use ExUnit.Case, async: true

  alias MessagingGateway.Webhooks.DeliveryReport

  @id "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"

  defp reason(r),
    do: DeliveryReport.validate(%{"message_id" => @id, "status" => "failed", "reason" => r})

  test "reason is bounded by codepoints, matching the varchar(255) column" do
    assert {:ok, %{reason: _}} = reason(String.duplicate("é", 255))
    # "e" + combining acute: 255 graphemes but 510 codepoints
    assert {:error, %{errors: [reason: _]}} = reason(String.duplicate("é", 255))
  end

  test "reason may not contain NUL" do
    assert {:error, %{errors: [reason: _]}} = reason("a\u0000b")
  end
end
