defmodule Hyperliquid.Manager do
  @moduledoc """
  Application manager responsible for handling WebSocket clients and subscriptions.

  This module provides functionality to manage WebSocket connections, user subscriptions,
  and stream workers in the Hyperliquid application. It acts as a central point for
  managing the state of active connections and subscriptions.

  ## Key Features

  - Initializes the application cache and starts initial streams
  - Manages user and non-user subscriptions
  - Provides utilities to start and stop stream workers
  - Handles automatic user subscription initialization
  - Offers functions to query the current state of subscriptions and workers

  ## Usage

  This module is typically used to manage WebSocket connections and subscriptions,
  as well as to query the current state of workers.

  Example:

      # Get all active subscriptions
      Hyperliquid.Manager.get_all_active_subs()

      # Start a new stream for a specific subscription
      Hyperliquid.Manager.maybe_start_stream(%{type: "allMids"})

      # Automatically start subscriptions for a user
      Hyperliquid.Manager.auto_start_user("0x1234...")
  """
  use GenServer
  require Logger

  alias Hyperliquid.Cache
  alias Hyperliquid.Api.Subscription
  alias Hyperliquid.Streamer.{Supervisor, Stream}

  @workers :worker_registry
  @users :user_registry

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    Cache.init()
    Supervisor.start_stream([%{type: "allMids"}])
    {:ok, %{}}
  end

  def get_subbed_users, do: Registry.select(@users, [{{:"$1", :_, :_}, [], [:"$1"]}])

  def get_active_non_user_subs, do:
    @workers
    |> Registry.select([{{:_, :_, :"$3"}, [], [:"$3"]}])
    |> Enum.flat_map(& &1.subs)
    |> Enum.filter(&!Map.has_key?(&1, :user))

  def get_active_user_subs, do:
    @users
    |> Registry.select([{{:_, :_, :"$3"}, [], [:"$3"]}])
    |> Enum.flat_map(& &1)
    |> Enum.filter(&Map.has_key?(&1, :user))

  def get_all_active_subs, do: get_active_user_subs() ++ get_active_non_user_subs()

  def get_worker_pids, do: Registry.select(@workers, [{{:_, :"$2", :_}, [], [:"$2"]}])

  def get_worker_ids, do: get_worker_pids() |> Enum.flat_map(&Registry.keys(@workers, &1))

  def get_workers, do:
    Supervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(&elem(&1, 1))

  def get_worker_pid_by_sub(match_sub), do: get_pid_by_sub(@workers, match_sub)

  def get_pid_by_sub(registry, match_sub) do
    results = Registry.select(registry, [
      {{:"$1", :"$2", :"$3"}, [], [{{:"$2", :"$3"}}]}
    ])

    case Enum.find(results, fn {_pid, state} ->
      Enum.any?(state.subs, fn sub -> sub == match_sub end)
    end) do
      {pid, _state} -> pid
      nil -> {:error, :not_found}
    end
  end

  def maybe_start_stream(sub) when is_map(sub) do
    subbed? = get_active_non_user_subs() |> Enum.member?(sub)

    if subbed? do
      Logger.warning("already subbed to this topic")
    else
      Supervisor.start_stream([sub])
    end
  end

  def kill_worker(pid), do: Supervisor.stop_child(pid)

  def auto_start_user(address, coin \\ nil) do
    address = String.downcase(address)

    get_subbed_users()
    |> Enum.map(&String.downcase(&1))
    |> Enum.member?(address)
    |> case do
      true -> Logger.warning("already subbed to user")
      _    -> Subscription.make_user_subs(address, coin) |> Supervisor.start_stream()
    end
  end

  def unsubscribe_all(pid) when is_pid(pid) do
    id = Registry.keys(@workers, pid) |> Enum.at(0)

    case id do
      nil -> Logger.warning("not a worker pid")
      _   -> Registry.values(@workers, id, pid) |> Enum.at(0)
    end
    |> Map.get(:subs)
    |> Enum.map(&Stream.unsubscribe(pid, &1))
  end

  def unsubscribe_all(id) when is_binary(id) do
    [{pid, %{subs: subs}}] = Registry.lookup(@workers, id)

    Enum.map(subs, &Stream.unsubscribe(pid, &1))
  end
end
