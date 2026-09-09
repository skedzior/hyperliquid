defmodule Hyperliquid.WebSocket.Supervisor do
  @moduledoc """
  Supervisor for the WebSocket subsystem.

  Children, in start order:

  1. `Hyperliquid.WebSocket.Registry` — unique registry of connections by key
  2. `Hyperliquid.WebSocket.Dispatch` — duplicate registry, channel => subscribers
  3. `Hyperliquid.WebSocket.Store` — owns the ETS tables, so the subscription
     book survives a Manager crash
  4. `Hyperliquid.WebSocket.Budget` — per-IP connect/message token buckets
  5. `Hyperliquid.WebSocket.ConnectionSupervisor` — DynamicSupervisor for sockets
  6. `Hyperliquid.WebSocket.SubscriberSupervisor` — DynamicSupervisor for the
     per-subscription consumer processes
  7. `Hyperliquid.WebSocket.Manager` — control plane

  The strategy is `:rest_for_one`, not `:one_for_all`: the Manager is last, so a
  Manager crash restarts only the Manager (which then re-adopts the live
  connections and the ETS subscription book) instead of tearing down every
  socket and every subscription. Restart intensity is raised so that a single
  flapping socket cannot take the subtree down with it.

  ## Usage

      children = [Hyperliquid.WebSocket.Supervisor]
      Supervisor.start_link(children, strategy: :one_for_one)
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Hyperliquid.WebSocket.Registry},
      {Registry, keys: :duplicate, name: Hyperliquid.WebSocket.Dispatch},
      Hyperliquid.WebSocket.Store,
      Hyperliquid.WebSocket.Budget,
      {DynamicSupervisor,
       name: Hyperliquid.WebSocket.ConnectionSupervisor,
       strategy: :one_for_one,
       max_restarts: 100,
       max_seconds: 60},
      {DynamicSupervisor,
       name: Hyperliquid.WebSocket.SubscriberSupervisor,
       strategy: :one_for_one,
       max_restarts: 100,
       max_seconds: 60},
      {Hyperliquid.WebSocket.Manager, name: Hyperliquid.WebSocket.Manager}
    ]

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 10, max_seconds: 60)
  end
end
