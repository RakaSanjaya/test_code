defmodule MessagingGatewayWeb.WebhookController do
  use MessagingGatewayWeb, :controller

  alias MessagingGateway.Messaging
  alias MessagingGateway.Webhooks.DeliveryReport

  action_fallback MessagingGatewayWeb.FallbackController

  # Reached only after VerifyWebhookSignature accepted the raw body.
  def vendor(conn, _params) do
    with {:ok, report} <- DeliveryReport.validate(conn.body_params),
         {:ok, result, message} <-
           Messaging.apply_status_update(report.message_id, report.status, report.reason) do
      json(conn, %{
        data: %{message_id: message.id, status: message.status, result: Atom.to_string(result)}
      })
    end
  end
end
