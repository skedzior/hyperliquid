defmodule Hyperliquid.Streamer.Supervisor do
  @moduledoc """
  Supervisor for WebSocket stream processes in the Hyperliquid application.

  This module implements a dynamic supervisor that manages WebSocket stream
  processes. It allows for dynamically starting and stopping stream processes,
  providing flexibility in managing multiple WebSocket connections.

  ## Key Features

  - Dynamically supervises WebSocket stream processes
  - Provides functions to start and stop individual stream processes
  - Allows querying of currently supervised children

  ## Usage

  This supervisor is typically started as part of your application's supervision tree.
  It can then be used to dynamically manage WebSocket stream processes.

  Example:

      # Start the supervisor
      {:ok, pid} = Hyperliquid.Streamer.Supervisor.start_link()

      # Start a new stream process
      {:ok, stream_pid} = Hyperliquid.Streamer.Supervisor.start_stream([%{type: "allMids"}])

      # Stop a stream process
      :ok = Hyperliquid.Streamer.Supervisor.stop_child(stream_pid)

  Note: This supervisor uses a :one_for_one strategy, meaning each child is
  supervised independently.
  """
  use DynamicSupervisor

  alias Hyperliquid.Streamer.Stream

  def start_link(_args) do
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
