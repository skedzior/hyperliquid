defmodule Hyperliquid.WebSocket.Store do
  @moduledoc """
  Owns the WebSocket layer's ETS tables.

  The tables outlive the `Hyperliquid.WebSocket.Manager` process on purpose: if
  the Manager crashes it restarts with the subscription book intact and re-adopts
  the live connections instead of orphaning every subscription.

  Tables (all public, read-concurrent):

    * `:ws_subscriptions` — `{subscription_id, %Manager.Subscription{}}`, the
      control-plane record.
    * `:ws_subscription_metrics` — `{subscription_id, count, last_at, recent_timestamps}`,
      written by `Hyperliquid.WebSocket.Subscriber` processes, never by the Manager.
  """

  use GenServer

  @tables [:ws_subscriptions, :ws_subscription_metrics]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Create the tables if they do not already exist (idempotent)."
  @spec ensure_tables() :: :ok
  def ensure_tables do
    Enum.each(@tables, &ensure_table/1)
    :ok
  end

  @doc "Create one named public table if it does not already exist (idempotent)."
  @spec ensure_table(atom()) :: :ok
  def ensure_table(table) do
    if :ets.whereis(table) == :undefined do
      :ets.new(table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  @doc "Table names owned by this process."
  @spec tables() :: [atom()]
  def tables, do: @tables

  @impl true
  def init(_opts) do
    ensure_tables()
    {:ok, %{}}
  end
end
