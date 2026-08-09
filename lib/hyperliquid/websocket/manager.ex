defmodule Hyperliquid.WebSocket.Manager do
  @moduledoc """
  WebSocket connection and subscription manager.

  Manages multiple WebSocket connections, routes subscriptions to appropriate
  connections, and provides a registry of active subscriptions.

  ## Connection Strategy

  All subscriptions share as few connections as possible within Hyperliquid's limits:

  - **Shared socket** (`"shared"`) — all `:shared` and `:dedicated` subscriptions
    land here. The `:dedicated` type is legacy; modules may still declare it but
    the manager treats it identically to `:shared`.

  - **First user socket** — when the first `:user_grouped` subscription is created,
    it is placed on the shared socket. No extra connection is opened.

  - **Per-user sockets** (`"user:<address>"`) — each additional unique user gets
    its own connection so that message routing remains unambiguous (the connection
    itself is the routing tag; user addresses are not guaranteed in WS responses).

  Because the shared socket carries mixed subscription types, the manager filters
  incoming messages by channel before dispatching to each subscription's callback.

  ## Usage

      # Subscribe to allMids (shared socket)
      {:ok, sub_id} = Manager.subscribe(Hyperliquid.Api.Subscription.AllMids, %{})

      # Subscribe to l2Book — also lands on the shared socket
      {:ok, sub_id} = Manager.subscribe(Hyperliquid.Api.Subscription.L2Book, %{
        coin: "BTC", nSigFigs: 5
      })

      # First user subscription — shares the existing shared socket
      {:ok, sub_id} = Manager.subscribe(Hyperliquid.Api.Subscription.UserFills, %{
        user: "0x1234..."
      })

      # Second user — gets its own socket
      {:ok, sub_id} = Manager.subscribe(Hyperliquid.Api.Subscription.UserFills, %{
        user: "0xabcd..."
      })

      # Unsubscribe
      :ok = Manager.unsubscribe(sub_id)

      # List active subscriptions
      Manager.list_subscriptions()

  ## Architecture

  The Manager uses a DynamicSupervisor to manage WebSocket connections.
  Each connection is a GenServer that handles the actual WebSocket communication.
  The Manager maintains:

  1. A registry of active subscriptions (ETS table)
  2. A mapping of connection keys to connection PIDs
  3. Connection metadata and per-subscription metrics
  """

  use GenServer
  require Logger

  @type subscription_id :: String.t()
  @type connection_type :: :shared | :dedicated | :user_grouped

  defmodule Subscription do
    @moduledoc "Represents an active subscription."

    @type t :: %__MODULE__{
            id: String.t(),
            module: module(),
            params: map(),
            key: String.t(),
            connection_type: atom(),
            connection_pid: pid() | nil,
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
      :connection_type,
      :connection_pid,
      :callback,
      :subscribed_at,
      message_count: 0,
      last_message_at: nil,
      message_timestamps: []
    ]
  end

  # ===================== Client API =====================

  @doc """
  Start the WebSocket manager.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribe to a WebSocket endpoint.

  ## Parameters

  - `module` - The subscription endpoint module
  - `params` - Subscription parameters
  - `callback` - Function to call with incoming messages (optional)

  ## Returns

  - `{:ok, subscription_id}` - Subscription created
  - `{:error, reason}` - Failed to subscribe
  """
  @spec subscribe(module(), map(), function() | nil) ::
          {:ok, subscription_id()} | {:error, term()}
  def subscribe(module, params, callback \\ nil) do
    GenServer.call(__MODULE__, {:subscribe, module, params, callback})
  end

  @doc """
  Unsubscribe from a WebSocket endpoint.

  ## Parameters

  - `subscription_id` - The subscription ID returned from subscribe/3

  ## Returns

  - `:ok` - Unsubscribed successfully
  - `{:error, :not_found}` - Subscription not found
  """
  @spec unsubscribe(subscription_id()) :: :ok | {:error, :not_found}
  def unsubscribe(subscription_id) do
    GenServer.call(__MODULE__, {:unsubscribe, subscription_id})
  end

  @doc """
  List all active subscriptions.
  """
  @spec list_subscriptions() :: [Subscription.t()]
  def list_subscriptions do
    GenServer.call(__MODULE__, :list_subscriptions)
  end

  @doc """
  Get subscription by ID.
  """
  @spec get_subscription(subscription_id()) :: {:ok, Subscription.t()} | {:error, :not_found}
  def get_subscription(subscription_id) do
    GenServer.call(__MODULE__, {:get_subscription, subscription_id})
  end

  @doc """
  List subscriptions for a specific user.
  """
  @spec list_user_subscriptions(String.t()) :: [Subscription.t()]
  def list_user_subscriptions(user_address) do
    GenServer.call(__MODULE__, {:list_user_subscriptions, user_address})
  end

  @doc """
  Get connection info for debugging.
  """
  @spec connection_info() :: map()
  def connection_info do
    GenServer.call(__MODULE__, :connection_info)
  end

  @doc """
  Get metrics for a specific subscription.

  ## Parameters

  - `subscription_id` - The subscription ID

  ## Returns

  - `{:ok, metrics}` - Subscription metrics
  - `{:error, :not_found}` - Subscription not found

  ## Metrics

  - `:message_count` - Total messages received
  - `:last_message_at` - Timestamp of last message
  - `:subscribed_at` - When subscription was created
  - `:messages_per_minute` - Average messages per minute
  - `:uptime_seconds` - Time since subscription started
  """
  @spec get_metrics(subscription_id()) :: {:ok, map()} | {:error, :not_found}
  def get_metrics(subscription_id) do
    GenServer.call(__MODULE__, {:get_metrics, subscription_id})
  end

  @doc """
  Get metrics for all subscriptions.
  """
  @spec list_all_metrics() :: [map()]
  def list_all_metrics do
    GenServer.call(__MODULE__, :list_all_metrics)
  end

  # ===================== Server Callbacks =====================

  @impl true
  def init(_opts) do
    # Create ETS table for subscriptions
    :ets.new(:ws_subscriptions, [:named_table, :set, :public, read_concurrency: true])

    state = %{
      # Map of connection_key => connection_pid
      connections: %{},
      # Map of subscription_id => subscription
      subscriptions: %{},
      # Counter for generating unique IDs
      counter: 0,
      # Millisecond timestamps of recent connection creations (for rate limiting)
      connection_timestamps: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, module, params, callback}, _from, state) do
    # Get subscription metadata from module
    info = get_subscription_info(module)
    connection_type = info.connection_type
    subscription_key = generate_subscription_key(module, params, connection_type)
    ws_url = get_ws_url(info)

    # Coerce numeric parameters for certain subscription types
    coerced_params = coerce_numeric_params(module, params)

    # Check if we already have an active subscription for this module+params
    case find_existing_subscription(state.subscriptions, module, coerced_params) do
      {:ok, existing_sub} ->
        # Already subscribed - update callback if provided and return existing ID
        if callback do
          updated_sub = %{existing_sub | callback: callback}
          :ets.insert(:ws_subscriptions, {existing_sub.id, updated_sub})
          subscriptions = Map.put(state.subscriptions, existing_sub.id, updated_sub)
          Logger.debug("Reusing existing subscription #{existing_sub.id} for #{inspect(module)}")
          {:reply, {:ok, existing_sub.id}, %{state | subscriptions: subscriptions}}
        else
          Logger.debug("Reusing existing subscription #{existing_sub.id} for #{inspect(module)}")
          {:reply, {:ok, existing_sub.id}, state}
        end

      :not_found ->
        # Enforce Hyperliquid rate limits before creating a new subscription
        with :ok <- check_subscription_limit(state),
             :ok <- check_user_limit(state, connection_type, params, ws_url) do
          # No existing subscription, create a new one
          sub_id = generate_subscription_id(state.counter)

          # Build the subscription request
          case module.build_request(coerced_params) do
            {:ok, request} ->
              # Determine which connection to use (may enforce connection limits)
              case get_or_create_connection(
                     connection_type,
                     subscription_key,
                     params,
                     ws_url,
                     state
                   ) do
                {:ok, connection_key, connection_pid, state} ->
                  # Create subscription record
                  subscription = %Subscription{
                    id: sub_id,
                    module: module,
                    params: params,
                    key: connection_key,
                    connection_type: connection_type,
                    connection_pid: connection_pid,
                    callback: callback,
                    subscribed_at: DateTime.utc_now()
                  }

                  # Store in ETS and state
                  :ets.insert(:ws_subscriptions, {sub_id, subscription})
                  subscriptions = Map.put(state.subscriptions, sub_id, subscription)

                  # Send subscription to connection
                  send_subscription(connection_pid, request, sub_id)

                  new_state = %{state | subscriptions: subscriptions, counter: state.counter + 1}

                  :telemetry.execute(
                    [:hyperliquid, :ws, :subscribe],
                    %{count: 1},
                    %{module: module, key: subscription_key}
                  )

                  Logger.info(
                    "Subscribed #{inspect(module)} with key #{subscription_key}, id: #{sub_id}"
                  )

                  {:reply, {:ok, sub_id}, new_state}

                {:error, reason} ->
                  {:reply, {:error, reason}, state}
              end

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:unsubscribe, subscription_id}, _from, state) do
    case Map.get(state.subscriptions, subscription_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      subscription ->
        # Remove from ETS
        :ets.delete(:ws_subscriptions, subscription_id)

        # Send unsubscribe to connection
        if subscription.connection_pid && Process.alive?(subscription.connection_pid) do
          send_unsubscription(subscription.connection_pid, subscription)
        end

        # Update state
        subscriptions = Map.delete(state.subscriptions, subscription_id)

        # Check if connection should be closed (no more subscriptions)
        state = maybe_close_connection(subscription.key, subscriptions, state)

        :telemetry.execute(
          [:hyperliquid, :ws, :unsubscribe],
          %{count: 1},
          %{subscription_id: subscription_id}
        )

        Logger.info("Unsubscribed #{subscription_id}")
        {:reply, :ok, %{state | subscriptions: subscriptions}}
    end
  end

  @impl true
  def handle_call(:list_subscriptions, _from, state) do
    subscriptions = Map.values(state.subscriptions)
    {:reply, subscriptions, state}
  end

  @impl true
  def handle_call({:get_subscription, subscription_id}, _from, state) do
    case Map.get(state.subscriptions, subscription_id) do
      nil -> {:reply, {:error, :not_found}, state}
      sub -> {:reply, {:ok, sub}, state}
    end
  end

  @impl true
  def handle_call({:list_user_subscriptions, user_address}, _from, state) do
    user_subs =
      state.subscriptions
      |> Map.values()
      |> Enum.filter(fn sub ->
        sub.params[:user] == user_address || sub.params["user"] == user_address
      end)

    {:reply, user_subs, state}
  end

  @impl true
  def handle_call(:connection_info, _from, state) do
    info = %{
      total_connections: map_size(state.connections),
      total_subscriptions: map_size(state.subscriptions),
      connections:
        Enum.map(state.connections, fn {key, pid} ->
          %{key: key, pid: pid, alive: Process.alive?(pid)}
        end)
    }

    {:reply, info, state}
  end

  @impl true
  def handle_call({:get_metrics, subscription_id}, _from, state) do
    case Map.get(state.subscriptions, subscription_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      sub ->
        metrics = calculate_metrics(sub)
        {:reply, {:ok, metrics}, state}
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
    # Remove failed subscriptions from tracking
    subscriptions =
      state.subscriptions
      |> Enum.reject(fn {id, _sub} -> id in failed_sub_ids end)
      |> Map.new()

    # Remove from ETS as well
    Enum.each(failed_sub_ids, fn id ->
      :ets.delete(:ws_subscriptions, id)
    end)

    Logger.error(
      "WebSocket error affects #{length(failed_sub_ids)} subscription(s): #{inspect(error_message)}"
    )

    # Call callbacks with error for failed subscriptions
    Enum.each(failed_sub_ids, fn sub_id ->
      case Map.get(state.subscriptions, sub_id) do
        nil ->
          :ok

        sub ->
          if sub.callback do
            error_event = %{
              channel: "error",
              subscription_id: sub.id,
              error: error_message
            }

            sub.callback.(error_event)
          end
      end
    end)

    {:noreply, %{state | subscriptions: subscriptions}}
  end

  def handle_info({:ws_error, connection_pid, error_message}, state) do
    # Legacy handler for errors without subscription IDs
    # Log which subscriptions are affected by this error
    affected_subs =
      state.subscriptions
      |> Map.values()
      |> Enum.filter(&(&1.connection_pid == connection_pid))

    Logger.error(
      "WebSocket error affects #{length(affected_subs)} subscription(s): #{inspect(error_message)}"
    )

    # Optionally call callbacks with error
    Enum.each(affected_subs, fn sub ->
      if sub.callback do
        # Wrap the error in a standardized format
        error_event = %{
          channel: "error",
          subscription_id: sub.id,
          error: error_message
        }

        sub.callback.(error_event)
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:ws_message, connection_pid, message}, state) do
    now = DateTime.utc_now()

    # Route message to matching subscription callbacks.
    # The shared socket carries mixed subscription types (shared, dedicated, and the first user),
    # so we filter by channel to avoid cross-dispatching (e.g. an allMids message should not
    # trigger an l2Book callback). Per-user connections only carry that user's subscriptions,
    # so filtering there is a no-op but still correct.
    subscriptions =
      state.subscriptions
      |> Enum.map(fn {id, sub} ->
        if sub.connection_pid == connection_pid && message_matches_subscription?(message, sub) do
          updated_sub = update_subscription_metrics(sub, now)
          :ets.insert(:ws_subscriptions, {id, updated_sub})
          maybe_store_event(sub.module, sub.params, message)
          if sub.callback, do: sub.callback.(message)
          {id, updated_sub}
        else
          {id, sub}
        end
      end)
      |> Map.new()

    {:noreply, %{state | subscriptions: subscriptions}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    Logger.warning("WebSocket connection #{inspect(pid)} down: #{inspect(reason)}")

    # Find and clean up connection
    {connection_key, _} =
      Enum.find(state.connections, {nil, nil}, fn {_key, conn_pid} ->
        conn_pid == pid
      end)

    connections =
      if connection_key do
        Map.delete(state.connections, connection_key)
      else
        state.connections
      end

    # Mark affected subscriptions as disconnected
    subscriptions =
      state.subscriptions
      |> Enum.map(fn {id, sub} ->
        if sub.connection_pid == pid do
          {id, %{sub | connection_pid: nil}}
        else
          {id, sub}
        end
      end)
      |> Map.new()

    {:noreply, %{state | connections: connections, subscriptions: subscriptions}}
  end

  # ===================== Private Functions =====================

  defp get_subscription_info(module) do
    # Ensure module is loaded before checking for exported functions
    Code.ensure_loaded(module)

    if function_exported?(module, :__subscription_info__, 0) do
      module.__subscription_info__()
    else
      # Default based on module name heuristics
      # This fallback should rarely be used - mainly for backwards compatibility
      module_name = to_string(module)

      connection_type =
        cond do
          String.contains?(module_name, "User") -> :user_grouped
          String.contains?(module_name, "OpenOrders") -> :user_grouped
          String.contains?(module_name, "Notification") -> :user_grouped
          String.contains?(module_name, "OrderUpdates") -> :user_grouped
          String.contains?(module_name, "L2Book") -> :dedicated
          String.contains?(module_name, "Explorer") -> :dedicated
          true -> :shared
        end

      # Try to infer ws_url for explorer modules
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
        request_type: module |> Module.split() |> List.last() |> Macro.underscore()
      }
    end
  end

  defp find_existing_subscription(subscriptions, module, params) do
    # Normalize params for comparison (convert string keys to atoms)
    normalized_params = normalize_params(params)

    # Use module-declared key_fields for dedup comparison (e.g., Candle uses [:coin, :interval])
    key_fields =
      if function_exported?(module, :__subscription_info__, 0) do
        module.__subscription_info__()[:key_fields] || []
      else
        []
      end

    existing =
      subscriptions
      |> Map.values()
      |> Enum.find(fn sub ->
        sub.module == module &&
          sub.connection_pid != nil &&
          Process.alive?(sub.connection_pid) &&
          params_match?(normalize_params(sub.params), normalized_params, key_fields)
      end)

    case existing do
      nil -> :not_found
      sub -> {:ok, sub}
    end
  end

  defp normalize_params(params) do
    params
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
    end)
    |> Map.new()
  rescue
    # If atom doesn't exist, just use string comparison
    ArgumentError -> params
  end

  defp params_match?(params1, params2, key_fields) when is_map(params1) and is_map(params2) do
    # Use module-declared key_fields if available, otherwise fall back to default keys
    keys =
      if key_fields != [] do
        key_fields
      else
        [:user, :coin, :dex]
      end

    Enum.all?(keys, fn key ->
      Map.get(params1, key) == Map.get(params2, key)
    end)
  end

  defp params_match?(_, _, _), do: false

  defp get_ws_url(info) do
    ws_url_value = info[:ws_url]

    Logger.debug(
      "get_ws_url: ws_url value = #{inspect(ws_url_value)}, is_function? = #{is_function(ws_url_value, 0)}"
    )

    result =
      case ws_url_value do
        nil -> Hyperliquid.Config.ws_url()
        url_fn when is_function(url_fn, 0) -> url_fn.()
        url when is_binary(url) -> url
      end

    Logger.debug("get_ws_url: resolved URL = #{result}")
    result
  end

  defp generate_subscription_key(module, params, connection_type) do
    base_type = get_request_type(module)

    case connection_type do
      :shared ->
        # All shared subscriptions use same connection
        "shared"

      :dedicated ->
        # Generate unique key from all params
        # e.g., "l2Book:BTC:5:nil" for L2Book with coin=BTC, nSigFigs=5
        param_parts =
          params
          |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
          |> Enum.map(fn {_k, v} -> to_string(v) end)
          |> Enum.join(":")

        "#{base_type}:#{param_parts}"

      :user_grouped ->
        # Group by user address
        user = params[:user] || params["user"] || "unknown"
        "user:#{user}"
    end
  end

  defp get_request_type(module) do
    if function_exported?(module, :__subscription_info__, 0) do
      module.__subscription_info__().request_type
    else
      # Extract from module name
      module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
    end
  end

  defp generate_subscription_id(counter) do
    timestamp = System.system_time(:millisecond)
    "sub_#{timestamp}_#{counter}"
  end

  # Returns {:ok, connection_key, pid, state} | {:error, reason}
  defp get_or_create_connection(connection_type, _subscription_key, params, ws_url, state) do
    # Include URL in connection key for different WS endpoints
    url_suffix =
      if ws_url != Hyperliquid.Config.ws_url(), do: ":#{URI.parse(ws_url).host}", else: ""

    connection_key =
      case connection_type do
        :shared -> "shared#{url_suffix}"
        # :dedicated is legacy — fold onto the shared socket
        :dedicated -> "shared#{url_suffix}"
        :user_grouped -> user_connection_key(params, state, url_suffix)
      end

    case Map.get(state.connections, connection_key) do
      nil ->
        # Would create a new connection — enforce connection count and rate limits
        with :ok <- check_connection_count_limit(state),
             :ok <- check_connection_rate_limit(state) do
          {:ok, pid} = start_connection(connection_key, ws_url)
          Process.monitor(pid)
          connections = Map.put(state.connections, connection_key, pid)
          state = track_connection_timestamp(%{state | connections: connections})
          {:ok, connection_key, pid, state}
        end

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, connection_key, pid, state}
        else
          # Connection died — check rate limit before replacing (count stays the same)
          with :ok <- check_connection_rate_limit(state) do
            {:ok, new_pid} = start_connection(connection_key, ws_url)
            Process.monitor(new_pid)
            connections = Map.put(state.connections, connection_key, new_pid)
            state = track_connection_timestamp(%{state | connections: connections})
            {:ok, connection_key, new_pid, state}
          end
        end
    end
  end

  # Returns the connection key for a user_grouped subscription.
  # The first unique user shares the existing shared socket (no new connection needed).
  # Each subsequent unique user gets its own "user:#{address}" connection so that
  # message routing remains unambiguous (user address is not guaranteed in WS responses).
  defp user_connection_key(params, state, url_suffix) do
    address = params[:user] || params["user"]
    shared_key = "shared#{url_suffix}"
    user_key = "user:#{address}#{url_suffix}"

    cond do
      # User already has a dedicated connection
      Map.has_key?(state.connections, user_key) ->
        user_key

      # User is already on the shared socket
      address in users_on_connection(state.subscriptions, shared_key) ->
        shared_key

      # First user — goes on the shared socket
      users_on_connection(state.subscriptions, shared_key) == [] ->
        shared_key

      # Additional user — gets its own connection
      true ->
        user_key
    end
  end

  # Returns the list of unique user addresses whose user_grouped subscriptions
  # are routed through the given connection key.
  defp users_on_connection(subscriptions, connection_key) do
    subscriptions
    |> Map.values()
    |> Enum.filter(fn sub ->
      sub.connection_type == :user_grouped && sub.key == connection_key
    end)
    |> Enum.map(fn sub -> sub.params[:user] || sub.params["user"] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  # ===================== Rate Limit Helpers =====================

  # Max 1000 simultaneous subscriptions (Hyperliquid limit)
  defp check_subscription_limit(state) do
    if map_size(state.subscriptions) >= Hyperliquid.Config.ws_max_subscriptions() do
      Logger.warning("WebSocket subscription limit reached (#{Hyperliquid.Config.ws_max_subscriptions()})")
      {:error, :subscription_limit_exceeded}
    else
      :ok
    end
  end

  # Max 10 unique users across user-specific subscriptions (Hyperliquid limit).
  # The first user shares the shared socket (no new connection consumed).
  # Each subsequent unique user needs its own connection, so we also check the
  # connection budget for those cases.
  defp check_user_limit(state, :user_grouped, params, ws_url) do
    new_user = params[:user] || params["user"]
    existing_users = unique_ws_users(state.subscriptions)

    if new_user not in existing_users do
      if length(existing_users) >= Hyperliquid.Config.ws_max_users() do
        Logger.warning(
          "WebSocket user limit reached (#{Hyperliquid.Config.ws_max_users()} unique users)"
        )

        {:error, :user_limit_exceeded}
      else
        # Check whether this user would require a new connection.
        # The first user lands on the shared socket; additional users each need one.
        url_suffix =
          if ws_url != Hyperliquid.Config.ws_url(), do: ":#{URI.parse(ws_url).host}", else: ""

        shared_key = "shared#{url_suffix}"
        users_on_shared = users_on_connection(state.subscriptions, shared_key)
        needs_new_connection = users_on_shared != []

        if needs_new_connection &&
             map_size(state.connections) >= Hyperliquid.Config.ws_max_connections() do
          Logger.warning(
            "WebSocket connection budget exhausted — cannot add new user (#{map_size(state.connections)}/#{Hyperliquid.Config.ws_max_connections()} connections in use)"
          )

          {:error, :connection_limit_exceeded}
        else
          :ok
        end
      end
    else
      :ok
    end
  end

  defp check_user_limit(_state, _connection_type, _params, _ws_url), do: :ok

  # Max 10 simultaneous connections (Hyperliquid limit)
  defp check_connection_count_limit(state) do
    if map_size(state.connections) >= Hyperliquid.Config.ws_max_connections() do
      Logger.warning("WebSocket connection limit reached (#{Hyperliquid.Config.ws_max_connections()})")
      {:error, :connection_limit_exceeded}
    else
      :ok
    end
  end

  # Max 30 new connections per minute (Hyperliquid limit)
  defp check_connection_rate_limit(state) do
    now = System.system_time(:millisecond)
    one_minute_ago = now - 60_000
    recent_count = Enum.count(state.connection_timestamps, &(&1 > one_minute_ago))

    if recent_count >= Hyperliquid.Config.ws_max_connections_per_minute() do
      Logger.warning(
        "WebSocket connection rate limit reached (#{Hyperliquid.Config.ws_max_connections_per_minute()} new connections/min)"
      )

      {:error, :connection_rate_exceeded}
    else
      :ok
    end
  end

  # Record a new connection timestamp and prune entries older than 1 minute
  defp track_connection_timestamp(state) do
    now = System.system_time(:millisecond)
    one_minute_ago = now - 60_000

    pruned =
      [now | state.connection_timestamps]
      |> Enum.filter(&(&1 > one_minute_ago))

    %{state | connection_timestamps: pruned}
  end

  # Returns the list of unique user addresses currently tracked in user_grouped subscriptions
  defp unique_ws_users(subscriptions) do
    subscriptions
    |> Map.values()
    |> Enum.filter(&(&1.connection_type == :user_grouped))
    |> Enum.map(fn sub -> sub.params[:user] || sub.params["user"] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp start_connection(connection_key, ws_url) do
    Logger.info("Starting WebSocket connection: #{connection_key} -> #{ws_url}")

    child_spec = {
      Hyperliquid.WebSocket.Connection,
      key: connection_key, manager: self(), url: ws_url
    }

    DynamicSupervisor.start_child(
      Hyperliquid.WebSocket.ConnectionSupervisor,
      child_spec
    )
  end

  defp send_subscription(connection_pid, request, subscription_id) do
    if connection_pid && Process.alive?(connection_pid) do
      Hyperliquid.WebSocket.Connection.subscribe(connection_pid, request, subscription_id)
    end
  end

  defp send_unsubscription(connection_pid, subscription) do
    if connection_pid && Process.alive?(connection_pid) do
      Hyperliquid.WebSocket.Connection.unsubscribe(connection_pid, subscription.id)
    end
  end

  defp maybe_close_connection(connection_key, subscriptions, state) do
    # Check if any subscriptions still use this connection
    still_used =
      subscriptions
      |> Map.values()
      |> Enum.any?(&(&1.key == connection_key))

    if still_used do
      state
    else
      case Map.get(state.connections, connection_key) do
        nil ->
          state

        pid ->
          # Terminate through the DynamicSupervisor
          DynamicSupervisor.terminate_child(
            Hyperliquid.WebSocket.ConnectionSupervisor,
            pid
          )

          Logger.info("Closing unused connection: #{connection_key}")
          %{state | connections: Map.delete(state.connections, connection_key)}
      end
    end
  end

  # Keep last 60 timestamps for calculating msgs/min
  @max_timestamps 60

  # Coerce string parameters to integers for subscription types that need it
  defp coerce_numeric_params(module, params) do
    module_name = to_string(module)

    # L2Book subscriptions need mantissa and nSigFigs as integers
    if String.contains?(module_name, "L2Book") do
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
      nil ->
        params

      value when is_integer(value) ->
        params

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int_value, _} -> Map.put(params, key, int_value)
          :error -> params
        end

      _other ->
        params
    end
  end

  defp update_subscription_metrics(sub, now) do
    # Add new timestamp and keep only last N
    timestamps = [now | sub.message_timestamps] |> Enum.take(@max_timestamps)

    %{
      sub
      | message_count: sub.message_count + 1,
        last_message_at: now,
        message_timestamps: timestamps
    }
  end

  defp calculate_metrics(%Subscription{} = sub) do
    now = DateTime.utc_now()
    uptime_seconds = DateTime.diff(now, sub.subscribed_at, :second)

    # Calculate msgs/min from total message count (accurate for all rates)
    messages_per_minute =
      if uptime_seconds > 0 do
        sub.message_count / uptime_seconds * 60
      else
        0.0
      end

    # Count recent messages from stored timestamps (may be capped at @max_timestamps)
    one_minute_ago = DateTime.add(now, -60, :second)

    recent_messages =
      Enum.count(sub.message_timestamps, fn ts ->
        DateTime.compare(ts, one_minute_ago) == :gt
      end)

    # Calculate actual message rate over the last stored window
    # This gives us the instantaneous rate from recent samples
    window_rate =
      if length(sub.message_timestamps) > 1 do
        oldest_timestamp = List.last(sub.message_timestamps)
        window_duration = DateTime.diff(now, oldest_timestamp, :second)

        if window_duration > 0 do
          length(sub.message_timestamps) / window_duration * 60
        else
          0.0
        end
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
      # Additional metric: instantaneous rate from recent window
      recent_rate_per_minute: round_if_float(window_rate)
    }
  end

  defp round_if_float(value) when is_float(value), do: Float.round(value, 2)
  defp round_if_float(value) when is_integer(value), do: value * 1.0
  defp round_if_float(value), do: value

  # Returns true if the WS message should be dispatched to the given subscription.
  # We match on message["channel"] against the subscription module's request_type.
  # Messages without a channel key (e.g., pong) are delivered to all subs on the connection.
  defp message_matches_subscription?(message, sub) do
    case message["channel"] do
      nil -> true
      channel -> channel == get_request_type(sub.module)
    end
  end

  # ===================== Storage Integration =====================

  # Check if module has storage enabled and store event asynchronously
  # subscription_params contains context like user address for user_grouped subscriptions
  defp maybe_store_event(module, subscription_params, message) do
    Logger.debug(
      "[Manager] Maybe Store #{inspect(module)} #{function_exported?(module, :storage_enabled?, 0)} #{inspect(module.storage_enabled?())}"
    )

    if function_exported?(module, :storage_enabled?, 0) and module.storage_enabled?() do
      # Extract the data portion from the WebSocket message
      # Messages typically have format: %{"channel" => "...", "data" => actual_data}
      event_data = extract_event_data(message)

      if event_data do
        # Merge subscription params (e.g., user) into event data for context
        storage_data = merge_subscription_context(event_data, subscription_params)
        Hyperliquid.Storage.Writer.store_async(module, storage_data)

        Logger.debug(
          "[Manager] SAVED with context: #{inspect(Map.keys(subscription_params || %{}))}"
        )
      end
    end
  rescue
    error ->
      Logger.warning(
        "[Manager] Storage failed for #{inspect(module)}: #{Exception.message(error)}"
      )
  end

  # Merge subscription params into event data for storage context
  defp merge_subscription_context(event_data, nil), do: event_data
  defp merge_subscription_context(event_data, params) when map_size(params) == 0, do: event_data

  defp merge_subscription_context(event_data, params) when is_list(event_data) do
    # For list events (like trades), merge context into each item
    Enum.map(event_data, fn item ->
      Map.merge(params, item)
    end)
  end

  defp merge_subscription_context(event_data, params) when is_map(event_data) do
    Map.merge(params, event_data)
  end

  defp merge_subscription_context(event_data, _params), do: event_data

  # Extract the actual event data from a WebSocket message
  # Handle both map and list data (e.g., trades come as a list, explorer blocks come as array)
  defp extract_event_data(%{"data" => data}), do: data
  defp extract_event_data(%{data: data}), do: data
  defp extract_event_data(message) when is_list(message), do: message
  defp extract_event_data(message) when is_map(message), do: message
  defp extract_event_data(_), do: nil
end
