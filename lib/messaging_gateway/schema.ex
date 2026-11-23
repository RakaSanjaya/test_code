defmodule MessagingGateway.Schema do
  @moduledoc """
  Shared schema defaults: UUID primary/foreign keys and microsecond UTC timestamps.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime_usec]

      @type t :: %__MODULE__{}
    end
  end
end
