defmodule MessagingGateway.Messaging do
  @moduledoc "Sending messages and applying delivery status updates."

  import Ecto.Query

  alias MessagingGateway.Billing
  alias MessagingGateway.Messaging.{Message, StatusMachine}
  alias MessagingGateway.Repo

  @doc """
  Applies a vendor status to a message under a row lock.

  Lock order (see README): message row first, then the tenant row (via refund).
  A transition to `failed` refunds `message.cost` exactly once.
  """
  @spec apply_status_update(term(), term(), String.t() | nil) ::
          {:ok, :updated | :unchanged, Message.t()}
          | {:error, :not_found | :invalid_status | :invalid_transition}
  def apply_status_update(message_id, status, reason) do
    with {:ok, id} <- cast_id(message_id),
         :ok <- validate_vendor_status(status) do
      Repo.transaction(fn -> locked_status_update(id, status, reason) end)
      |> case do
        {:ok, {result, message}} -> {:ok, result, message}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp locked_status_update(id, status, reason) do
    message = Repo.one(from m in Message, where: m.id == ^id, lock: "FOR UPDATE")

    with %Message{} <- message || {:error, :not_found},
         :apply <- StatusMachine.check(message.status, status) do
      updated = update_status!(message, status, reason)

      if status == "failed" do
        case Billing.refund(message.tenant_id, message.id, message.cost) do
          {:ok, _} -> {:updated, updated}
          {:error, error} -> Repo.rollback(error)
        end
      else
        {:updated, updated}
      end
    else
      :noop -> {:unchanged, message}
      :invalid -> Repo.rollback(:invalid_transition)
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp update_status!(message, "failed", reason) do
    message |> Ecto.Changeset.change(status: "failed", failure_reason: reason) |> Repo.update!()
  end

  defp update_status!(message, status, _reason) do
    message |> Ecto.Changeset.change(status: status) |> Repo.update!()
  end

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :not_found}
    end
  end

  defp validate_vendor_status(status) do
    if status in StatusMachine.vendor_statuses(), do: :ok, else: {:error, :invalid_status}
  end
end
