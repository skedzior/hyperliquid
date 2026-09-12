defmodule Hyperliquid.WebSocket.Manager do
  @moduledoc """
  WebSocket connection and subscription manager (control plane only).

  ## Connection strategy — packing, not one-socket-per-user

  Hyperliquid's unique-user cap is **15 per connection** (empirically verified;
  the published "10 unique users" figure is wrong, and the cap is *not* per IP).
  Tracking of a user lingers ~15 s after its last subscription goes away.

  The Manager therefore bin-packs subscriptions onto connections: a new
  subscription is placed on the first existing connection that has headroom
  (`Hyperliquid.WebSocket.Packer`), and a new connection is opened only when
  every existing one is full. With the default limits that is 15 users per
  socket rather than one, i.e. ~15x the previous capacity for the same
  connection budget.

  Channels whose events carry no user attribution (`orderUpdates`, `userEvents`,
  `notification`) are limited to one user per connection, because two users of
  those channels on one socket cannot be told apart.

  ## Data plane

  The Manager never touches inbound market data. Connections dispatch frames
  directly to per-subscription `Hyperliquid.WebSocket.Subscriber` processes
  through the `Hyperliquid.WebSocket.Dispatch` registry, matching on the full
  subscription identity (channel + coin/user/interval/dex), so an `l2Book`
  subscriber for BTC never receives ETH data and a slow consumer callback cannot
  stall any other feed.

  ## Usage

      # Subscribe with a callback (runs in the subscription's own process)
      {:ok, sub_id} = Manager.subscribe(Hyperliquid.Api.Subscription.AllMids, %{})

      {:ok, sub_id} = Manager.subscribe(Hyperliquid.Api.Subscription.L2Book, %{
        coin: "BTC", nSigFigs: 5
      }, fn msg -> IO.inspect(msg) end)

      # Without a callback, messages are delivered to the calling process as
      #   {:hyperliquid_ws, subscription_id, message}

      :ok = Manager.unsubscribe(sub_id)
      Manager.list_subscriptions()

  The subscribing process is monitored: when it dies its subscriptions are torn
  down automatically, freeing the rate-limit slots they held.
  """

  use GenServer
  require Logger

  alias Hyperliquid.WebSocket.{Limits, Packer, Store, Subscriber, SubscriptionKey}

  @type subscription_id :: String.t()
  @type connection_type :: :shared | :dedicated | :user_grouped

  @subscriptions_table :ws_subscriptions
  @prune_interval 5_000

  defmodule Subscription do
    @moduledoc "Represents an active subscription."

    @type t :: %__MODULE__{
            id: String.t(),
            module: module(),
            params: map(),
            key: String.t(),
            identity: Hyperliquid.WebSocket.SubscriptionKey.t() | nil,
            connection_type: atom(),
            connection_pid: pid() | nil,
            subscriber_pid: pid() | nil,
            owner: pid() | nil,
            callback: function() | nil,
            subscribed_at: DateTime.t(),
            message_count: non_neg_integer(),
            last_message_at: DateTime.t() | nil,
            message_timestamps: [DateTime.t()]
          }

    defstruct [
      :id,
      :module,
      :params,
      :key,
      :identity,
      :connection_type,
      :connection_pid,
      :subscriber_pid,
      :owner,
      :callback,
      :subscribed_at,
      message_count: 0,
      last_message_at: nil,
      message_timestamps: []
    ]
  end

  # ===================== Client API =====================

  @doc "Start the WebSocket manager."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribe to a WebSocket endpoint.

  - `module` - The subscription endpoint module
  - `params` - Subscription parameters
  - `callback` - Optional 1-arity function, run in the subscription's own
    process. Without it, messages are sent to the calling process as
    `{:hyperliquid_ws, subscription_id, message}`.
  """
  @spec subscribe(module(), map(), function() | nil, GenServer.server()) ::
          {:ok, subscription_id()} | {:error, term()}
  def subscribe(module, params, callback \\ nil, server \\ __MODULE__) do
    GenServer.call(server, {:subscribe, module, params, callback, self()})
  end

  @doc "Unsubscribe from a WebSocket endpoint."
  @spec unsubscribe(subscription_id(), GenServer.server()) :: :ok | {:error, :not_found}
  def unsubscribe(subscription_id, server \\ __MODULE__) do
    GenServer.call(server, {:unsubscribe, subscription_id})
  end

  @doc "List all active subscriptions."
  @spec list_subscriptions(GenServer.server()) :: [Subscription.t()]
  def list_subscriptions(server \\ __MODULE__) do
    GenServer.call(server, :list_subscriptions)
  end

  @doc "Get subscription by ID."
  @spec get_subscription(subscription_id(), GenServer.server()) ::
          {:ok, Subscription.t()} | {:error, :not_found}
  def get_subscription(subscription_id, server \\ __MODULE__) do
    GenServer.call(server, {:get_subscription, subscription_id})
  end

  @doc "List subscriptions for a specific user."
  @spec list_user_subscriptions(String.t(), GenServer.server()) :: [Subscription.t()]
  def list_user_subscriptions(user_address, server \\ __MODULE__) do
    GenServer.call(server, {:list_user_subscriptions, user_address})
  end

  @doc """
  Connection info for debugging: per-connection subscription counts, tracked
  users and remaining user headroom.
  """
  @spec connection_info(GenServer.server()) :: map()
  def connection_info(server \\ __MODULE__) do
    GenServer.call(server, :connection_info)
  end

  @doc """
  Get metrics for a specific subscription.

  Returns `:message_count`, `:last_message_at`, `:subscribed_at`,
  `:messages_per_minute`, `:messages_last_minute`, `:recent_rate_per_minute`
  and `:uptime_seconds`.
  """
  @spec get_metrics(subscription_id(), GenServer.server()) :: {:ok, map()} | {:error, :not_found}
  def get_metrics(subscription_id, server \\ __MODULE__) do
    GenServer.call(server, {:get_metrics, subscription_id})
  end

  @doc "Get metrics for all subscriptions."
  @spec list_all_metrics(GenServer.server()) :: [map()]
  def list_all_metrics(server \\ __MODULE__) do
    GenServer.call(server, :list_all_metrics)
  end

  # ===================== Server Callbacks =====================

  @impl true
  def init(opts) do
    Store.ensure_tables()
    table = Keyword.get(opts, :table, @subscriptions_table)
    Store.ensure_table(table)
    Process.flag(:trap_exit, true)
    Process.send_after(self(), :prune, @prune_interval)

    state = %{
      # connection_key => %{pid, ref, url, slot}
      connections: %{},
      # subscription_id => %Subscription{}
      subscriptions: %{},
      # subscriber_pid => subscription_id
      subscribers: %{},
      counter: 0,
      table: table,
      connection_opts: Keyword.get(opts, :connection_opts, []),
      supervisor:
        Keyword.get(opts, :connection_supervisor, Hyperliquid.WebSocket.ConnectionSupervisor),
      subscriber_supervisor:
        Keyword.get(opts, :subscriber_supervisor, Hyperliquid.WebSocket.SubscriberSupervisor)
    }

    {:ok, adopt_existing(state)}
  end

  @impl true
  def handle_call({:subscribe, module, params, callback, owner}, _from, state) do
    info = get_subscription_info(module)
    coerced_params = coerce_numeric_params(module, params)
    identity = SubscriptionKey.identity(module, coerced_params)
    ws_url = get_ws_url(info)

    with :ok <- check_subscription_limit(state),
         {:ok, request} <- module.build_request(coerced_params),
         {:ok, conn_key, state} <- place_subscription(state, identity, ws_url) do
      sub_id = generate_subscription_id(state.counter)
      conn = Map.fetch!(state.connections, conn_key)

      case start_subscriber(state, sub_id, module, coerced_params, identity, callback, owner) do
        {:ok, subscriber_pid} ->
          subscription = %Subscription{
            id: sub_id,
            module: module,
            params: coerced_params,
            key: conn_key,
            identity: identity,
            connection_type: info.connection_type,
            connection_pid: conn.pid,
            subscriber_pid: subscriber_pid,
            owner: owner,
            callback: callback,
            subscribed_at: DateTime.utc_now()
          }

          # Only put a subscribe frame on the wire if this identity is not
          # already subscribed on this connection.
          unless identity_on_connection?(state.subscriptions, conn_key, identity) do
            Hyperliquid.WebSocket.Connection.subscribe(conn.pid, request, sub_id)
          end

          :ets.insert(state.table, {sub_id, subscription})

          state = %{
            state
            | subscriptions: Map.put(state.subscriptions, sub_id, subscription),
              subscribers: Map.put(state.subscribers, subscriber_pid, sub_id),
              counter: state.counter + 1
          }

          :telemetry.execute(
            [:hyperliquid, :ws, :subscribe],
            %{count: 1},
            %{module: module, key: SubscriptionKey.to_string(identity)}
          )

          Logger.info(
            "Subscribed #{inspect(module)} (#{SubscriptionKey.to_string(identity)}) on #{conn_key}, id: #{sub_id}"
          )

          {:reply, {:ok, sub_id}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unsubscribe, subscription_id}, _from, state) do
    case Map.get(state.subscriptions, subscription_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      subscription ->
        state = remove_subscription(state, subscription)

        :telemetry.execute(
          [:hyperliquid, :ws, :unsubscribe],
          %{count: 1},
          %{subscription_id: subscription_id}
        )

        Logger.info("Unsubscribed #{subscription_id}")
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:list_subscriptions, _from, state) do
    {:reply, Enum.map(Map.values(state.subscriptions), &with_metrics/1), state}
  end

  @impl true
  def handle_call({:get_subscription, subscription_id}, _from, state) do
    case Map.get(state.subscriptions, subscription_id) do
      nil -> {:reply, {:error, :not_found}, state}
      sub -> {:reply, {:ok, with_metrics(sub)}, state}
    end
  end

  @impl true
  def handle_call({:list_user_subscriptions, user_address}, _from, state) do
    wanted = String.downcase(user_address)

    user_subs =
      state.subscriptions
      |> Map.values()
      |> Enum.filter(fn sub -> SubscriptionKey.user(sub.identity) == wanted end)
      |> Enum.map(&with_metrics/1)

    {:reply, user_subs, state}
  end

  @impl true
  def handle_call(:connection_info, _from, state) do
    now = System.monotonic_time(:millisecond)

    info = %{
      total_connections: map_size(state.connections),
      total_subscriptions: map_size(state.subscriptions),
      limits: Limits.all(),
      connections:
        Enum.map(state.connections, fn {key, conn} ->
          %{
            key: key,
            pid: conn.pid,
            url: conn.url,
            alive: is_pid(conn.pid) and Process.alive?(conn.pid),
            subscriptions: conn.slot.subscriptions,
            users: MapSet.to_list(conn.slot.users),
            tracked_users: MapSet.size(Packer.tracked_users(conn.slot, now)),
            user_headroom: Packer.headroom(conn.slot, now)
          }
        end)
    }

    {:reply, info, state}
  end

  @impl true
  def handle_call({:get_metrics, subscription_id}, _from, state) do
    case Map.get(state.subscriptions, subscription_id) do
      nil -> {:reply, {:error, :not_found}, state}
      sub -> {:reply, {:ok, calculate_metrics(sub)}, state}
    end
  end

  @impl true
  def handle_call(:list_all_metrics, _from, state) do
    metrics =
      state.subscriptions
      |> Map.values()
      |> Enum.map(fn sub ->
        sub
        |> calculate_metrics()
        |> Map.put(:subscription_id, sub.id)
        |> Map.put(:module, sub.module)
        |> Map.put(:params, sub.params)
      end)

    {:reply, metrics, state}
  end

  @impl true
  def handle_info({:ws_error, _connection_pid, error_message, failed_sub_ids}, state) do
    Logger.error(
      "WebSocket error affects #{length(failed_sub_ids)} subscription(s): #{inspect(error_message)}"
    )

    state =
      Enum.reduce(failed_sub_ids, state, fn sub_id, acc ->
        case Map.get(acc.subscriptions, sub_id) do
          nil ->
            acc

          sub ->
            if is_pid(sub.subscriber_pid) and Process.alive?(sub.subscriber_pid) do
              send(sub.subscriber_pid, {:hyperliquid_ws_error, error_message})
            end

            remove_subscription(acc, sub)
        end
      end)

    {:noreply, state}
  end

  def handle_info({:ws_error, connection_pid, error_message}, state) do
    failed =
      state.subscriptions
      |> Map.values()
      |> Enum.filter(&(&1.connection_pid == connection_pid))
      |> Enum.map(& &1.id)

    handle_info({:ws_error, connection_pid, error_message, failed}, state)
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    cond do
      Map.has_key?(state.subscribers, pid) ->
        sub_id = Map.fetch!(state.subscribers, pid)

        case Map.get(state.subscriptions, sub_id) do
          nil -> {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}
          sub -> {:noreply, remove_subscription(state, sub, skip_subscriber_stop: true)}
        end

      connection_key(state, pid) != nil ->
        key = connection_key(state, pid)

        Logger.warning(
          "WebSocket connection #{key} (#{inspect(pid)}) down: #{inspect(reason)} — reattaching"
        )

        state = put_in(state.connections[key], %{Map.fetch!(state.connections, key) | pid: nil})
        Process.send_after(self(), {:reattach, key, 0}, 100)
        {:noreply, state}

      true ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:reattach, key, attempt}, state) do
    case Map.get(state.connections, key) do
      nil ->
        {:noreply, state}

      %{pid: pid} when is_pid(pid) ->
        {:noreply, state}

      conn ->
        case Hyperliquid.WebSocket.Connection.lookup(key) do
          {:ok, pid} ->
            {:noreply, reattach_connection(state, key, conn, pid)}

          {:error, :not_found} when attempt < 5 ->
            Process.send_after(self(), {:reattach, key, attempt + 1}, 200 * (attempt + 1))
            {:noreply, state}

          {:error, :not_found} ->
            case start_connection(state, key, conn.url) do
              {:ok, pid} ->
                {:noreply, reattach_connection(state, key, conn, pid)}

              {:error, reason} ->
                Logger.error("Could not restart connection #{key}: #{inspect(reason)}")
                {:noreply, drop_connection(state, key)}
            end
        end
    end
  end

  @impl true
  def handle_info(:prune, state) do
    Process.send_after(self(), :prune, @prune_interval)
    now = System.monotonic_time(:millisecond)

    state =
      Enum.reduce(Map.keys(state.connections), state, fn key, acc ->
        conn = Map.fetch!(acc.connections, key)
        slot = Packer.prune(conn.slot, now)
        acc = put_in(acc.connections[key], %{conn | slot: slot})

        if slot.subscriptions == 0 and map_size(slot.lingering) == 0 do
          close_connection(acc, key)
        else
          acc
        end
      end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  def handle_info(_msg, state), do: {:noreply, state}

  # ===================== Placement =====================

  defp place_subscription(state, identity, ws_url) do
    now = System.monotonic_time(:millisecond)
    demand = demand_for(identity, ws_url)
    slots = state.connections |> Map.values() |> Enum.map(& &1.slot)

    case Packer.place(slots, demand, now) do
      {:ok, key} ->
        {:ok, key, track_placement(state, key, demand)}

      :new ->
        key = next_connection_key(state, ws_url)

        case start_connection(state, key, ws_url) do
          {:ok, pid} ->
            ref = Process.monitor(pid)
            slot = Packer.new_connection(key, ws_url)

            state =
              put_in(state.connections[key], %{pid: pid, ref: ref, url: ws_url, slot: slot})

            {:ok, key, track_placement(state, key, demand)}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning(
          "No WebSocket capacity for #{SubscriptionKey.to_string(identity)}: #{reason}"
        )

        {:error, reason}
    end
  end

  defp demand_for(identity, ws_url) do
    %{
      url: ws_url,
      user: SubscriptionKey.user(identity),
      group_a?: SubscriptionKey.group_a?(identity)
    }
  end

  defp track_placement(state, key, demand) do
    update_in(state.connections[key].slot, &Packer.add(&1, demand))
  end

  defp next_connection_key(state, ws_url) do
    host = URI.parse(ws_url).host || "default"

    Stream.iterate(1, &(&1 + 1))
    |> Enum.find_value(fn n ->
      key = "#{host}:conn:#{n}"
      if Map.has_key?(state.connections, key), do: nil, else: key
    end)
  end

  defp identity_on_connection?(subscriptions, conn_key, identity) do
    subscriptions
    |> Map.values()
    |> Enum.any?(fn sub ->
      sub.key == conn_key and SubscriptionKey.same?(sub.identity, identity)
    end)
  end

  # ===================== Teardown =====================

  defp remove_subscription(state, subscription, opts \\ []) do
    :ets.delete(state.table, subscription.id)
    Subscriber.forget(subscription.id)

    subscriptions = Map.delete(state.subscriptions, subscription.id)

    unless Keyword.get(opts, :skip_subscriber_stop, false) do
      stop_subscriber(state, subscription.subscriber_pid)
    end

    # Only tell the server to unsubscribe when nothing else on this connection
    # holds the same identity.
    unless identity_on_connection?(subscriptions, subscription.key, subscription.identity) do
      if is_pid(subscription.connection_pid) and Process.alive?(subscription.connection_pid) do
        Hyperliquid.WebSocket.Connection.unsubscribe(
          subscription.connection_pid,
          subscription.id
        )
      end
    end

    state = %{
      state
      | subscriptions: subscriptions,
        subscribers: Map.delete(state.subscribers, subscription.subscriber_pid)
    }

    release_capacity(state, subscription, subscriptions)
  end

  defp release_capacity(state, subscription, subscriptions) do
    case Map.get(state.connections, subscription.key) do
      nil ->
        state

      conn ->
        now = System.monotonic_time(:millisecond)
        user = SubscriptionKey.user(subscription.identity)

        still_present? =
          user != nil and
            Enum.any?(Map.values(subscriptions), fn sub ->
              sub.key == subscription.key and SubscriptionKey.user(sub.identity) == user
            end)

        demand = %{
          url: conn.url,
          user: user,
          group_a?: SubscriptionKey.group_a?(subscription.identity)
        }

        slot = Packer.remove(conn.slot, demand, still_present?, now)
        put_in(state.connections[subscription.key], %{conn | slot: slot})
    end
  end

  defp close_connection(state, key) do
    case Map.get(state.connections, key) do
      nil ->
        state

      conn ->
        if conn.ref, do: Process.demonitor(conn.ref, [:flush])

        if is_pid(conn.pid) do
          DynamicSupervisor.terminate_child(state.supervisor, conn.pid)
        end

        Logger.info("Closing idle WebSocket connection: #{key}")
        drop_connection(state, key)
    end
  end

  defp drop_connection(state, key) do
    %{state | connections: Map.delete(state.connections, key)}
  end

  defp connection_key(state, pid) do
    Enum.find_value(state.connections, fn {key, conn} -> if conn.pid == pid, do: key end)
  end

  # After a connection restart: adopt the new pid and replay every subscription
  # that was routed through it, so a crash never orphans subscriptions.
  defp reattach_connection(state, key, conn, pid) do
    ref = Process.monitor(pid)
    state = put_in(state.connections[key], %{conn | pid: pid, ref: ref})

    table = state.table

    replayed =
      state.subscriptions
      |> Map.values()
      |> Enum.filter(&(&1.key == key))
      |> Enum.uniq_by(&SubscriptionKey.to_string(&1.identity))

    Enum.each(replayed, fn sub ->
      case sub.module.build_request(sub.params) do
        {:ok, request} -> Hyperliquid.WebSocket.Connection.subscribe(pid, request, sub.id)
        {:error, reason} -> Logger.error("Cannot replay #{sub.id}: #{inspect(reason)}")
      end
    end)

    subscriptions =
      Map.new(state.subscriptions, fn {id, sub} ->
        if sub.key == key do
          sub = %{sub | connection_pid: pid}
          :ets.insert(table, {id, sub})
          {id, sub}
        else
          {id, sub}
        end
      end)

    Logger.info("Reattached #{length(replayed)} subscription(s) to #{key}")
    %{state | subscriptions: subscriptions}
  end

  # A restarted Manager re-adopts live connections (registered in the Registry)
  # and the subscription book that survives in ETS.
  defp adopt_existing(state) do
    state.table
    |> :ets.tab2list()
    |> Enum.reduce(state, fn {sub_id, sub}, acc ->
      # Subscriber processes are linked to the previous Manager's supervisor and
      # may be gone; drop records whose subscriber died.
      if is_pid(sub.subscriber_pid) and Process.alive?(sub.subscriber_pid) do
        acc
        |> put_in([:subscriptions, sub_id], sub)
        |> put_in([:subscribers, sub.subscriber_pid], sub_id)
      else
        :ets.delete(state.table, sub_id)
        acc
      end
    end)
    |> adopt_connections()
  end

  defp adopt_connections(state) do
    now = System.monotonic_time(:millisecond)

    state.subscriptions
    |> Map.values()
    |> Enum.reduce(state, fn sub, acc ->
      key = sub.key

      acc =
        case Map.get(acc.connections, key) do
          nil ->
            case Hyperliquid.WebSocket.Connection.lookup(key) do
              {:ok, pid} ->
                ref = Process.monitor(pid)
                url = Hyperliquid.Config.ws_url()

                put_in(acc.connections[key], %{
                  pid: pid,
                  ref: ref,
                  url: url,
                  slot: Packer.new_connection(key, url)
                })

              {:error, :not_found} ->
                acc
            end

          _ ->
            acc
        end

      if Map.has_key?(acc.connections, key) do
        demand = %{
          url: acc.connections[key].url,
          user: SubscriptionKey.user(sub.identity),
          group_a?: SubscriptionKey.group_a?(sub.identity)
        }

        update_in(acc.connections[key].slot, &(&1 |> Packer.add(demand) |> Packer.prune(now)))
      else
        acc
      end
    end)
  end

  # ===================== Process helpers =====================

  defp start_connection(state, key, ws_url) do
    Logger.info("Starting WebSocket connection: #{key} -> #{ws_url}")

    child_spec = {
      Hyperliquid.WebSocket.Connection,
      [key: key, manager: self(), url: ws_url] ++ state.connection_opts
    }

    case DynamicSupervisor.start_child(state.supervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_subscriber(state, sub_id, module, params, identity, callback, owner) do
    spec =
      {Subscriber,
       [
         sub_id: sub_id,
         module: module,
         params: params,
         key: identity,
         callback: callback,
         owner: owner
       ]}

    case DynamicSupervisor.start_child(state.subscriber_supervisor, spec) do
      {:ok, pid} ->
        Process.monitor(pid)
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stop_subscriber(state, pid) when is_pid(pid) do
    if Process.alive?(pid) do
      DynamicSupervisor.terminate_child(state.subscriber_supervisor, pid)
    end

    :ok
  end

  defp stop_subscriber(_state, _pid), do: :ok

  # ===================== Limits =====================

  defp check_subscription_limit(state) do
    if map_size(state.subscriptions) >= Limits.max_subscriptions() do
      Logger.warning("WebSocket subscription limit reached (#{Limits.max_subscriptions()})")
      {:error, :subscription_limit_exceeded}
    else
      :ok
    end
  end

  # ===================== Metadata =====================

  defp get_subscription_info(module) do
    Code.ensure_loaded(module)

    if function_exported?(module, :__subscription_info__, 0) do
      module.__subscription_info__()
    else
      module_name = to_string(module)

      connection_type =
        cond do
          String.contains?(module_name, "User") -> :user_grouped
          String.contains?(module_name, "OpenOrders") -> :user_grouped
          String.contains?(module_name, "Notification") -> :user_grouped
          String.contains?(module_name, "OrderUpdates") -> :user_grouped
          true -> :shared
        end

      ws_url =
        if String.contains?(module_name, "Explorer") do
          &Hyperliquid.Config.rpc_ws_url/0
        else
          nil
        end

      Logger.warning(
        "Module #{module} does not export __subscription_info__/0, using heuristic fallback. Consider recompiling."
      )

      %{
        connection_type: connection_type,
        ws_url: ws_url,
        key_fields: [],
        request_type: module |> Module.split() |> List.last() |> Macro.underscore()
      }
    end
  end

  defp get_ws_url(info) do
    case info[:ws_url] do
      nil -> Hyperliquid.Config.ws_url()
      url_fn when is_function(url_fn, 0) -> url_fn.()
      url when is_binary(url) -> url
    end
  end

  defp generate_subscription_id(counter) do
    "sub_#{System.system_time(:millisecond)}_#{counter}"
  end

  # L2Book subscriptions need mantissa/nSigFigs as integers
  defp coerce_numeric_params(module, params) do
    if String.contains?(to_string(module), "L2Book") do
      params
      |> coerce_param_to_int(:mantissa)
      |> coerce_param_to_int(:nSigFigs)
      |> coerce_param_to_int("mantissa")
      |> coerce_param_to_int("nSigFigs")
    else
      params
    end
  end

  defp coerce_param_to_int(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {int_value, _} -> Map.put(params, key, int_value)
          :error -> params
        end

      _ ->
        params
    end
  end

  # ===================== Metrics =====================

  defp with_metrics(%Subscription{} = sub) do
    m = Subscriber.metrics(sub.id)

    %{
      sub
      | message_count: m.message_count,
        last_message_at: m.last_message_at,
        message_timestamps: m.message_timestamps
    }
  end

  defp calculate_metrics(%Subscription{} = sub) do
    sub = with_metrics(sub)
    now = DateTime.utc_now()
    uptime_seconds = DateTime.diff(now, sub.subscribed_at, :second)

    messages_per_minute =
      if uptime_seconds > 0, do: sub.message_count / uptime_seconds * 60, else: 0.0

    one_minute_ago = DateTime.add(now, -60, :second)

    recent_messages =
      Enum.count(sub.message_timestamps, &(DateTime.compare(&1, one_minute_ago) == :gt))

    window_rate =
      if length(sub.message_timestamps) > 1 do
        oldest = List.last(sub.message_timestamps)
        duration = DateTime.diff(now, oldest, :second)
        if duration > 0, do: length(sub.message_timestamps) / duration * 60, else: 0.0
      else
        0.0
      end

    %{
      message_count: sub.message_count,
      last_message_at: sub.last_message_at,
      subscribed_at: sub.subscribed_at,
      uptime_seconds: uptime_seconds,
      messages_per_minute: round_if_float(messages_per_minute),
      messages_last_minute: recent_messages,
      recent_rate_per_minute: round_if_float(window_rate)
    }
  end

  defp round_if_float(value) when is_float(value), do: Float.round(value, 2)
  defp round_if_float(value) when is_integer(value), do: value * 1.0
  defp round_if_float(value), do: value
end
