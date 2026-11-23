defmodule MessagingGateway.RateLimiter do
  @moduledoc """
  Fixed-window rate limiter on a public ETS table.

  Counting is a single atomic `:ets.update_counter/4`, so concurrent requests can
  never over-admit. The GenServer only owns the table and periodically sweeps
  expired buckets. Limits are per node; a multi-node deployment would need a
  shared store (Redis, Hammer with a distributed backend).
  """

  use GenServer

  @table :messaging_gateway_rate_limits
  @sweep_every_ms 60_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec hit(term(), pos_integer(), pos_integer(), integer()) ::
          :ok | {:error, :rate_limited, pos_integer()}
  def hit(key, limit, window_ms, now_ms \\ System.system_time(:millisecond)) do
    window = div(now_ms, window_ms)
    bucket = {key, window_ms, window}
    expires_at = (window + 1) * window_ms

    count = :ets.update_counter(@table, bucket, {2, 1}, {bucket, 0, expires_at})

    if count > limit, do: {:error, :rate_limited, expires_at - now_ms}, else: :ok
  end

  @doc "Deletes buckets whose window ended before `now_ms`; returns how many were removed."
  @spec sweep(integer()) :: non_neg_integer()
  def sweep(now_ms \\ System.system_time(:millisecond)) do
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now_ms}], [true]}])
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      write_concurrency: true,
      read_concurrency: true
    ])

    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep()
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_every_ms)
end
