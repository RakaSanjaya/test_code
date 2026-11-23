defmodule MessagingGateway.Messaging.StatusMachine do
  @moduledoc """
  Message delivery lifecycle:

      queued -> sent -> delivered
      queued -> failed
      sent   -> failed

  `delivered` and `failed` are final. Repeating the current status is a no-op,
  which is what makes vendor retries idempotent.
  """

  @statuses ~w(queued sent delivered failed)
  @vendor_statuses ~w(sent delivered failed)
  @final ~w(delivered failed)
  @transitions %{"queued" => ~w(sent failed), "sent" => ~w(delivered failed)}

  @spec vendor_statuses() :: [String.t()]
  def vendor_statuses, do: @vendor_statuses

  @spec final?(String.t()) :: boolean()
  def final?(status), do: status in @final

  @spec check(String.t(), String.t()) :: :apply | :noop | :invalid
  def check(from, to) when from == to and from in @statuses, do: :noop

  def check(from, to) do
    if to in Map.get(@transitions, from, []), do: :apply, else: :invalid
  end
end
