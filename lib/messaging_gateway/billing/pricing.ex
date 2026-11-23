defmodule MessagingGateway.Billing.Pricing do
  @moduledoc "Server-side price table. Client input never influences a price."

  @prices %{"authentication" => 300, "utility" => 500, "marketing" => 1000}
  @categories ["authentication", "utility", "marketing"]

  @spec categories() :: [String.t()]
  def categories, do: @categories

  @spec price_for(term()) :: {:ok, pos_integer()} | {:error, :unknown_category}
  def price_for(category) when is_map_key(@prices, category),
    do: {:ok, Map.fetch!(@prices, category)}

  def price_for(_), do: {:error, :unknown_category}
end
