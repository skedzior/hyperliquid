defmodule Hyperliquid.Application do
  @moduledoc false

  use Application

  @workers :worker_registry
  @users :user_registry
  @cache :hyperliquid

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Hyperliquid.PubSub},
      {Registry, [keys: :unique, name: @workers]},
      {Registry, [keys: :unique, name: @users]},
      {Cachex, name: @cache},
      {Hyperliquid.Cache.Updater, []},
      Hyperliquid.Streamer.Supervisor,
      Hyperliquid.Manager
    ]

    opts = [strategy: :one_for_one, name: Hyperliquid.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
