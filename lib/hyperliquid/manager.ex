defmodule Hyperliquid.Manager do
  use GenServer

  alias Hyperliquid.Cache
  alias Hyperliquid.Api.Subscription
  alias Hyperliquid.Streamer.{Supervisor, Stream}

  @workers :worker_registry
  @users :user_registry

  @max_ws_conns 100
  @max_ws_user_conns 10
  @max_ws_subscriptions 1_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    Cache.init()
    Supervisor.start_stream([%{type: "allMids"}])
    {:ok, %{}}
  end

  def subscribed?(sub, registry), do: Enum.member?(get_active_subs(registry) , sub)

  def get_subbed_users do
    @users
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
  end

  def get_active_subs(registry) do
    registry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  def get_unique_pids do
    @workers
    |> Registry.select([{{:_, :"$1", :_}, [], [:"$1"]}])
    |> Enum.uniq()
  end

  def get_workers do
    DynamicSupervisor.which_children(Supervisor)
    |> Enum.map(&elem(&1, 1))
  end

  def get_worker_count do
    get_workers() |> Enum.count()
  end

  # def find_userless_pids do
  #   registry = get_unique_pids() |> MapSet.new()

  #   get_workers()
  #   |> MapSet.new()
  #   |> MapSet.difference(registry)
  #   |> MapSet.to_list()
  # end

  # TODO: choose pid at random from workers instead of Enum.at(0)
  # def maybe_start_stream(sub) when is_map(sub) do
  #   key = Subscription.to_key(sub)
  #   subbed = get_active_subs() |> Enum.member?(key)
  #   pid = get_workers() |> Enum.at(0)

  #   cond do
  #     subbed -> IO.inspect("already subbed to this topic")
  #     !is_nil(pid) -> Stream.subscribe(pid, sub)
  #     is_nil(pid) -> Supervisor.start_stream([sub])
  #   end
  # end

  # def maybe_start_stream(address) do
  #   subbed = get_subbed_users() |> Enum.member?(address)
  #   pid = find_userless_pids() |> Enum.at(0)
  #   worker_count = get_worker_count()
  #   IO.inspect({subbed, pid, worker_count, find_userless_pids()})
  #   # TODO: may need to async await task
  #   cond do
  #     subbed -> IO.inspect("already subbed to this address")
  #     worker_count < @max_ws_clients -> async_auto_start_user(address)
  #     !is_nil(pid) -> async_auto_start_user(pid, address)
  #     true -> throw("max ws conns reached")
  #   end
  # end

  # defp async_auto_start_user(pid, address) do
  #   task = Task.async(fn -> auto_start_user(pid, address) end)
  #   Task.await(task)
  # end

  # defp async_auto_start_user(address) do
  #   task = Task.async(fn -> auto_start_user(address) end)
  #   Task.await(task)
  # end

  def auto_start_user(address) do
    address
    |> Subscription.make_user_subs()
    |> Supervisor.start_stream()
  end

  def auto_start_user(pid, address) do
    address
    |> Subscription.make_user_subs()
    |> then(&Stream.subscribe(pid, &1))
  end

  # def unsubscribe_all do
  #   @registry
  #   |> Registry.select([{{:"$1", :"$2", :"$3", }, [], [:"$2"]}])
  #   |> Enum.uniq()
  #   |> Enum.flat_map(&Registry.keys(@registry, &1))
  #   |> Enum.flat_map(&Registry.lookup(@registry, &1))
  #   |> Enum.map(fn {pid, sub} ->
  #     Stream.unsubscribe(pid, sub)
  #   end)
  # end

  # # def terminate_innactive do
  # #   WebSockex.send_frame(pid, {:close, %{}})
  # # end

  # def unsubscribe_topic(address, topic_key) do
  #   [{pid, topic}] = Registry.lookup(@registry, {address, topic_key})
  #   Stream.unsubscribe(pid, topic)
  # end
end
