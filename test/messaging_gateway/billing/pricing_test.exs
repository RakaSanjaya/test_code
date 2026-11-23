defmodule MessagingGateway.Billing.PricingTest do
  use ExUnit.Case, async: true

  alias MessagingGateway.Billing.Pricing

  test "server-side price table" do
    assert Pricing.price_for("authentication") == {:ok, 300}
    assert Pricing.price_for("utility") == {:ok, 500}
    assert Pricing.price_for("marketing") == {:ok, 1000}
    assert Pricing.price_for("AUTHENTICATION") == {:error, :unknown_category}
    assert Pricing.price_for(nil) == {:error, :unknown_category}
    assert Pricing.categories() == ["authentication", "utility", "marketing"]
  end
end
