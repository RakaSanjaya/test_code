defmodule MessagingGateway.Vendor.MockTest do
  use ExUnit.Case, async: true

  alias MessagingGateway.Messaging.Message
  alias MessagingGateway.Vendor

  test "mock vendor" do
    assert {:ok, "mock_" <> _} = Vendor.Mock.deliver(%Message{recipient: "+6281234567890"})
    assert {:error, :simulated_failure} = Vendor.Mock.deliver(%Message{recipient: "+9991234567"})
  end
end
