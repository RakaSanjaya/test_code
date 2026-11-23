defmodule MessagingGateway.Messaging do
  @moduledoc "Sending messages and applying delivery status updates."

  import Ecto.Query

  alias Ecto.Multi
  alias MessagingGateway.Accounts.Tenant
  alias MessagingGateway.Billing
  alias MessagingGateway.Billing.Pricing
  alias MessagingGateway.Dispatch.Worker

  alias MessagingGateway.Messaging.{
    Channel,
    Message,
    SendRequest,
    StatusMachine,
    Template,
    TemplateMatcher
  }

  alias MessagingGateway.Repo

  @type send_error ::
          Ecto.Changeset.t()
          | :invalid_idempotency_key
          | :idempotency_key_reused
          | :channel_not_found
          | :channel_inactive
          | :template_not_found
          | :template_not_approved
          | :template_mismatch
          | :insufficient_balance
          | :tenant_suspended

  @doc """
  Sends a message on behalf of an authenticated tenant.

  Only `tenant.id` is used from the struct: the balance is never trusted from
  memory. Category and cost are resolved server-side from the tenant's own
  template (if `template_code` is given) or channel. The message insert, the
  atomic debit, the ledger row and the dispatch job commit together or not at all.

  With an `Idempotency-Key`, a repeat of the same request returns the original
  message (`:replayed`) without charging again; reusing the key for a different
  request is refused.
  """
  @spec send_message(Tenant.t(), map(), term()) ::
          {:ok, Message.t(), :created | :replayed} | {:error, send_error()}
  def send_message(%Tenant{id: tenant_id}, params, idempotency_key) do
    with {:ok, key} <- SendRequest.validate_idempotency_key(idempotency_key),
         {:ok, req} <- SendRequest.validate(params) do
      fingerprint = SendRequest.fingerprint(req)

      case find_existing(tenant_id, key, fingerprint) do
        :none -> create_message(tenant_id, req, key, fingerprint)
        result -> result
      end
    end
  end

  @spec get_message(Ecto.UUID.t(), term()) :: {:ok, Message.t()} | {:error, :not_found}
  def get_message(tenant_id, id) do
    with {:ok, uuid} <- cast_id(id),
         %Message{} = message <-
           Repo.one(from m in Message, where: m.tenant_id == ^tenant_id and m.id == ^uuid) do
      {:ok, message}
    else
      _ -> {:error, :not_found}
    end
  end

  defp find_existing(_tenant_id, nil, _fingerprint), do: :none

  defp find_existing(tenant_id, key, fingerprint) do
    query = from m in Message, where: m.tenant_id == ^tenant_id and m.idempotency_key == ^key

    case Repo.one(query) do
      nil -> :none
      %Message{request_fingerprint: ^fingerprint} = message -> {:ok, message, :replayed}
      %Message{} -> {:error, :idempotency_key_reused}
    end
  end

  defp create_message(tenant_id, req, key, fingerprint) do
    with {:ok, channel} <- fetch_channel(tenant_id, req.channel_id),
         {:ok, category} <- resolve_category(tenant_id, channel, req),
         {:ok, cost} <- Pricing.price_for(category) do
      attrs = %{
        tenant_id: tenant_id,
        channel_id: channel.id,
        idempotency_key: key,
        request_fingerprint: fingerprint,
        recipient: req.recipient,
        content: req.text,
        template_code: req.template_code,
        category: category,
        cost: cost,
        status: "queued",
        metadata: req.metadata
      }

      # Lock order: insert message, then lock the tenant row via the debit (see README).
      Multi.new()
      |> Multi.insert(:message, Message.create_changeset(%Message{}, attrs))
      |> Multi.run(:debit, fn _repo, %{message: m} -> Billing.debit(tenant_id, m.id, cost) end)
      |> Oban.insert(:dispatch_job, fn %{message: m} -> Worker.new(%{"message_id" => m.id}) end)
      |> Repo.transaction()
      |> handle_create_result(tenant_id, key, fingerprint)
    end
  end

  defp handle_create_result({:ok, %{message: message}}, _tenant_id, _key, _fp),
    do: {:ok, message, :created}

  defp handle_create_result({:error, :debit, reason, _}, _tenant_id, _key, _fp),
    do: {:error, reason}

  defp handle_create_result({:error, :message, changeset, _}, tenant_id, key, fingerprint) do
    # A concurrent request with the same key committed first: replay it (or refuse reuse).
    with {_, opts} <- changeset.errors[:idempotency_key],
         :unique <- opts[:constraint],
         result when result != :none <- find_existing(tenant_id, key, fingerprint) do
      result
    else
      _ -> {:error, changeset}
    end
  end

  defp fetch_channel(tenant_id, channel_id) do
    case Repo.one(from c in Channel, where: c.id == ^channel_id and c.tenant_id == ^tenant_id) do
      nil -> {:error, :channel_not_found}
      %Channel{active: false} -> {:error, :channel_inactive}
      %Channel{} = channel -> {:ok, channel}
    end
  end

  defp resolve_category(_tenant_id, channel, %SendRequest{template_code: nil}),
    do: {:ok, channel.default_category}

  defp resolve_category(tenant_id, _channel, %SendRequest{template_code: code, text: text}) do
    query = from t in Template, where: t.tenant_id == ^tenant_id and t.code == ^code

    case Repo.one(query) do
      nil ->
        {:error, :template_not_found}

      %Template{status: status} when status != "approved" ->
        {:error, :template_not_approved}

      %Template{} = template ->
        if TemplateMatcher.matches?(template.body_pattern, text),
          do: {:ok, template.category},
          else: {:error, :template_mismatch}
    end
  end

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
      if status == "failed", do: refund!(message)
      {:updated, updated}
    else
      :noop -> {:unchanged, message}
      :invalid -> Repo.rollback(:invalid_transition)
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp refund!(message) do
    case Billing.refund(message.tenant_id, message.id, message.cost) do
      {:ok, _} -> :ok
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
