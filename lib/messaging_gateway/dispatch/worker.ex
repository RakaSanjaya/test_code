defmodule MessagingGateway.Dispatch.Worker do
  @moduledoc """
  Hands a queued message to the vendor.

  The job is inserted in the same transaction as the debit (transactional
  outbox), and its args hold only the message id so message content never
  lands in `oban_jobs`. If the vendor still rejects the message on the final
  attempt, the message is failed and refunded.
  """

  use Oban.Worker, queue: :dispatch, max_attempts: 3

  require Logger

  alias MessagingGateway.Messaging
  alias MessagingGateway.Messaging.Message
  alias MessagingGateway.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => id}, attempt: attempt, max_attempts: max}) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Message{} = message <- Repo.get(Message, uuid) do
      dispatch(message, attempt, max)
    else
      _ -> {:cancel, :message_not_found}
    end
  end

  defp dispatch(%Message{status: "queued"} = message, attempt, max) do
    vendor = Application.fetch_env!(:messaging_gateway, :vendor)

    case vendor.deliver(message) do
      {:ok, _vendor_ref} ->
        # :invalid_transition means a webhook already moved it on; nothing to do.
        _ = Messaging.apply_status_update(message.id, "sent", nil)
        :ok

      {:error, reason} when attempt < max ->
        Logger.warning(
          "vendor_dispatch_failed message_id=#{message.id} attempt=#{attempt} reason=#{inspect(reason)}"
        )

        {:error, :vendor_error}

      {:error, reason} ->
        Logger.warning(
          "vendor_dispatch_gave_up message_id=#{message.id} attempt=#{attempt} reason=#{inspect(reason)}"
        )

        _ = Messaging.apply_status_update(message.id, "failed", "dispatch_failed")
        :ok
    end
  end

  defp dispatch(%Message{}, _attempt, _max), do: :ok
end
