defmodule MessagingGateway.Vendor.Mock do
  @moduledoc """
  Simulated provider: recipients starting with `+999` fail, everything else is accepted.
  Delivery reports arrive later through the signed webhook.
  """

  @behaviour MessagingGateway.Vendor

  alias MessagingGateway.Messaging.Message

  @impl true
  def deliver(%Message{recipient: "+999" <> _}), do: {:error, :simulated_failure}
  def deliver(%Message{}), do: {:ok, "mock_" <> Ecto.UUID.generate()}
end
