defmodule MessagingGatewayWeb.MessageJSON do
  @moduledoc """
  Message representation. `content` is deliberately omitted: OTP codes and other
  message bodies are never echoed back over the API (data minimisation).
  """

  alias MessagingGateway.Messaging.Message

  def show(%{message: %Message{} = m}) do
    %{
      data: %{
        id: m.id,
        channel_id: m.channel_id,
        recipient: m.recipient,
        template_code: m.template_code,
        category: m.category,
        cost: m.cost,
        status: m.status,
        failure_reason: m.failure_reason,
        metadata: m.metadata,
        inserted_at: m.inserted_at,
        updated_at: m.updated_at
      }
    }
  end
end
