defmodule Hyperliquid.Streamer.Supervisor do
  use DynamicSupervisor

  alias Hyperliquid.Streamer.Stream

  def start_link(args \\ []) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def children do
    DynamicSupervisor.which_children(__MODULE__)
  end

  def start_stream(args \\ []) do
    DynamicSupervisor.start_child(__MODULE__, {Stream, args})
  end

  def stop_child(pids) when is_list(pids), do: Enum.map(pids, &stop_child(&1))

  def stop_child(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
# Hyperliquid.Streamer.Supervisor.children
