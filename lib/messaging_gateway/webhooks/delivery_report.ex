defmodule MessagingGateway.Webhooks.DeliveryReport do
  @moduledoc "Validates a vendor delivery report payload (after its signature was verified)."
  use Ecto.Schema
  import Ecto.Changeset

  alias MessagingGateway.Messaging.StatusMachine

  @primary_key false
  embedded_schema do
    field :message_id, Ecto.UUID
    field :status, :string
    field :reason, :string
  end

  @spec validate(map()) ::
          {:ok, %{message_id: String.t(), status: String.t(), reason: String.t() | nil}}
          | {:error, Ecto.Changeset.t()}
  def validate(params) when is_map(params) do
    %__MODULE__{}
    |> cast(params, [:message_id, :status, :reason])
    |> validate_required([:message_id, :status])
    |> validate_inclusion(:status, StatusMachine.vendor_statuses())
    |> validate_length(:reason, max: 255)
    |> apply_action(:validate)
    |> case do
      {:ok, report} -> {:ok, Map.take(report, [:message_id, :status, :reason])}
      error -> error
    end
  end
end
