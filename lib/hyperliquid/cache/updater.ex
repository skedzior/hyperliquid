defmodule Hyperliquid.Cache.Updater do
  use GenServer
  alias Hyperliquid.Cache

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update_cache, state) do
    Cache.init()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    interval = Application.get_env(:hyperliquid, __MODULE__)[:update_interval] || :timer.minutes(5)
    Process.send_after(self(), :update_cache, interval)
  end

  def set_update_interval(interval) when is_integer(interval) and interval > 0 do
    :ok = Application.put_env(:hyperliquid, __MODULE__, update_interval: interval)
  end
end
