defmodule MessagingGateway.Vendor do
  @moduledoc "Behaviour for outbound SMS/WhatsApp providers."

  alias MessagingGateway.Messaging.Message

  @callback deliver(Message.t()) :: {:ok, vendor_ref :: String.t()} | {:error, term()}
end
