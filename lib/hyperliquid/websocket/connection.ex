defmodule Hyperliquid.WebSocket.Connection do
  @moduledoc """
  A single WebSocket connection to Hyperliquid, with non-blocking connect,
  jittered reconnect and paced (re)subscription.

  Design notes:

    * **Nothing on the subscribe path blocks.** `subscribe/3` and `unsubscribe/2`
      are casts; connecting is fully asynchronous (`:gun_up` / `:gun_upgrade`
      messages, never `:gun.await_up/2`), so the Manager is never held up by a
      TCP+TLS handshake.
    * **Frames are dispatched straight to subscribers.** The connection decodes a
      frame and fans it out through the `Hyperliquid.WebSocket.Dispatch` registry
      using the full subscription identity (channel + coin/user/interval/dex), so
      a BTC `l2Book` subscriber never sees ETH data and consumer callbacks never
      run in this process or in the Manager.
    * **Reconnects are budgeted.** Backoff is exponential with jitter, and every
      dial and every batch of subscribe frames is charged against the shared
      per-IP `Hyperliquid.WebSocket.Budget`, so a mass disconnect cannot storm
      the rate limits.

  ## Usage

  Typically managed by `Hyperliquid.WebSocket.Manager`, but usable directly:

      {:ok, pid} = Connection.start_link(key: "conn:1", manager: self(), url: url)
      Connection.subscribe(pid, %{type: "l2Book", coin: "BTC"}, "sub_123")
      Connection.unsubscribe(pid, "sub_123")
  """

  use GenServer
  require Logger

  alias Hyperliquid.WebSocket.{Budget, Limits, SubscriptionKey}

  @default_url "wss://api.hyperliquid.xyz/ws"
  @heartbeat_interval 30_000
  @connect_timeout 15_000
  @base_reconnect_delay 1_000
  @max_reconnect_delay 60_000

  defmodule State do
    @moduledoc false
    defstruct [
      :key,
      :manager,
      :url,
      :conn,
      :stream_ref,
      :subscriptions,
      :reconnect_attempts,
      :heartbeat_ref,
      :connect_timer,
      :flush_ref,
      :status,
      :transport,
      pending_subscriptions: %{},
      outbox: []
    ]
  end

  # ===================== Client API =====================

  @doc """
  Start a WebSocket connection.

  ## Options

  - `:key` - Required. Connection identifier
  - `:manager` - Required. Manager PID for control-plane messages
  - `:url` - WebSocket URL (default: #{@default_url})
  - `:transport` - Module implementing the gun-like transport (tests inject a fake)
  """
  def start_link(opts) do
    key = Keyword.fetch!(opts, :key)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(key))
  end

  @doc """
  Subscribe to a channel on this connection.

  Asynchronous: the request is stored immediately and sent as soon as the socket
  is up. Never blocks the caller.
  """
  @spec subscribe(pid() | String.t(), map(), String.t()) :: :ok | {:error, term()}
  def subscribe(connection, request, subscription_id) when is_pid(connection) do
    GenServer.cast(connection, {:subscribe, request, subscription_id})
  end

  def subscribe(key, request, subscription_id) when is_binary(key) do
    case lookup(key) do
      {:ok, pid} -> subscribe(pid, request, subscription_id)
      error -> error
    end
  end

  @doc "Unsubscribe from a channel. Asynchronous."
  @spec unsubscribe(pid() | String.t(), String.t()) :: :ok | {:error, term()}
  def unsubscribe(connection, subscription_id) when is_pid(connection) do
    GenServer.cast(connection, {:unsubscribe, subscription_id})
  end

  def unsubscribe(key, subscription_id) when is_binary(key) do
    case lookup(key) do
      {:ok, pid} -> unsubscribe(pid, subscription_id)
      error -> error
    end
  end

  @doc "Get connection status. Short timeout — never blocks a caller for long."
  @spec status(pid() | String.t()) :: map() | {:error, term()}
  def status(connection) when is_pid(connection) do
    GenServer.call(connection, :status, 1_000)
  catch
    :exit, _ -> {:error, :unavailable}
  end

  def status(key) when is_binary(key) do
    case lookup(key) do
      {:ok, pid} -> status(pid)
      error -> error
    end
  end

  @doc "Lookup connection by key."
  @spec lookup(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def lookup(key) do
    case Registry.lookup(Hyperliquid.WebSocket.Registry, key) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Reconnect delay for `attempt`, in milliseconds.

  Exponential (1s, 2s, 4s, ... capped at 60s) with jitter over the lower half of
  each bucket, so sockets that dropped together do not redial in lockstep.
  """
  @spec backoff_delay(non_neg_integer()) :: pos_integer()
  def backoff_delay(attempt) do
    {low, high} = backoff_range(attempt)
    low + :rand.uniform(high - low + 1) - 1
  end

  @doc "The `{min, max}` delay bounds for `attempt` (jitter window)."
  @spec backoff_range(non_neg_integer()) :: {pos_integer(), pos_integer()}
  def backoff_range(attempt) do
    ceiling =
      @base_reconnect_delay
      |> Kernel.*(round(:math.pow(2, min(attempt, 16))))
      |> min(@max_reconnect_delay)

    {div(ceiling, 2), ceiling}
  end

  # ===================== Server Callbacks =====================

  @impl true
  def init(opts) do
    state = %State{
      key: Keyword.fetch!(opts, :key),
      manager: Keyword.fetch!(opts, :manager),
      url: Keyword.get(opts, :url, @default_url),
      transport: Keyword.get(opts, :transport, :gun),
      subscriptions: %{},
      reconnect_attempts: 0,
      status: :disconnected
    }

    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_cast({:subscribe, request, subscription_id}, state) do
    state = %{
      state
      | subscriptions: Map.put(state.subscriptions, subscription_id, request),
        pending_subscriptions: Map.put(state.pending_subscriptions, subscription_id, request)
    }

    {:noreply, enqueue(state, [%{method: "subscribe", subscription: request}])}
  end

  @impl true
  def handle_cast({:unsubscribe, subscription_id}, state) do
    case Map.get(state.subscriptions, subscription_id) do
      nil ->
        {:noreply, state}

      request ->
        state = %{
          state
          | subscriptions: Map.delete(state.subscriptions, subscription_id),
            pending_subscriptions: Map.delete(state.pending_subscriptions, subscription_id)
        }

        {:noreply, enqueue(state, [%{method: "unsubscribe", subscription: request}])}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      key: state.key,
      status: state.status,
      subscriptions: map_size(state.subscriptions),
      queued: length(state.outbox),
      reconnect_attempts: state.reconnect_attempts
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case Budget.take_connection() do
      {:error, {:rate_limited, retry_after}} ->
        Logger.debug(
          "WebSocket connect for #{state.key} deferred #{retry_after}ms (per-IP connect budget)"
        )

        Process.send_after(self(), :connect, retry_after + :rand.uniform(250))
        {:noreply, %{state | status: :reconnecting}}

      :ok ->
        do_connect(state)
    end
  end

  @impl true
  def handle_info(:connect_timeout, %State{status: status} = state)
      when status in [:opening, :upgrading] do
    Logger.warning("WebSocket connect timed out (#{state.key})")
    handle_disconnect(state)
  end

  def handle_info(:connect_timeout, state), do: {:noreply, state}

  @impl true
  def handle_info(:heartbeat, state) do
    if state.status == :connected do
      send_message(state, %{method: "ping"})
      heartbeat_ref = Process.send_after(self(), :heartbeat, @heartbeat_interval)
      {:noreply, %{state | heartbeat_ref: heartbeat_ref}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:reconnect, state) do
    send(self(), :connect)
    {:noreply, state}
  end

  @impl true
  def handle_info(:flush_outbox, state) do
    {:noreply, flush_outbox(%{state | flush_ref: nil})}
  end

  @impl true
  def handle_info({:gun_up, conn, _protocol}, %State{conn: conn} = state) do
    uri = URI.parse(state.url)
    stream_ref = transport_ws_upgrade(state, conn, uri.path || "/")
    {:noreply, %{state | stream_ref: stream_ref, status: :upgrading}}
  end

  def handle_info({:gun_up, _conn, _protocol}, state), do: {:noreply, state}

  @impl true
  def handle_info({:gun_upgrade, _conn, _stream_ref, ["websocket"], _headers}, state) do
    Logger.info("WebSocket connected: #{state.key}")

    :telemetry.execute([:hyperliquid, :ws, :connect, :stop], %{duration: 0}, %{key: state.key})

    if state.connect_timer, do: Process.cancel_timer(state.connect_timer)
    heartbeat_ref = Process.send_after(self(), :heartbeat, @heartbeat_interval)

    # Reset the backoff only once the *upgrade* succeeds. A server that accepts
    # TCP but rejects the upgrade (the shape of a connection-limit rejection)
    # must keep backing off rather than redialling once a second forever.
    state = %{
      state
      | status: :connected,
        reconnect_attempts: 0,
        heartbeat_ref: heartbeat_ref,
        connect_timer: nil
    }

    {:noreply, resubscribe_all(state)}
  end

  @impl true
  def handle_info({:gun_ws, _conn, _stream_ref, {:text, data}}, state) do
    :telemetry.execute([:hyperliquid, :ws, :message, :received], %{count: 1}, %{key: state.key})

    case Jason.decode(data) do
      {:ok, message} ->
        handle_ws_message(message, state)

      {:error, reason} ->
        Logger.warning("Failed to decode WebSocket message: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info({:gun_ws, _conn, _stream_ref, {:close, code, reason}}, state) do
    Logger.warning("WebSocket closed (#{state.key}): #{code} - #{reason}")
    handle_disconnect(state)
  end

  def handle_info({:gun_ws, _conn, _stream_ref, :close}, state) do
    Logger.warning("WebSocket closed (#{state.key})")
    handle_disconnect(state)
  end

  @impl true
  def handle_info({:gun_down, _conn, _protocol, reason, _killed}, state) do
    Logger.warning("WebSocket down (#{state.key}): #{inspect(reason)}")
    handle_disconnect(state)
  end

  def handle_info({:gun_down, _conn, _protocol, reason}, state) do
    Logger.warning("WebSocket down (#{state.key}): #{inspect(reason)}")
    handle_disconnect(state)
  end

  @impl true
  def handle_info({:gun_error, _conn, _stream_ref, reason}, state) do
    Logger.error("WebSocket error (#{state.key}): #{inspect(reason)}")
    handle_disconnect(state)
  end

  def handle_info({:gun_error, _conn, reason}, state) do
    Logger.error("WebSocket error (#{state.key}): #{inspect(reason)}")
    handle_disconnect(state)
  end

  @impl true
  def handle_info({:gun_response, _conn, _stream_ref, _fin, status, _headers}, state) do
    Logger.warning("WebSocket upgrade rejected (#{state.key}): HTTP #{status}")
    handle_disconnect(state)
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Connection terminating (#{state.key}): #{inspect(reason)}")

    if state.heartbeat_ref, do: Process.cancel_timer(state.heartbeat_ref)
    if state.connect_timer, do: Process.cancel_timer(state.connect_timer)
    if state.conn, do: transport_close(state, state.conn)

    :ok
  end

  # ===================== Private Functions =====================

  defp via_tuple(key) do
    {:via, Registry, {Hyperliquid.WebSocket.Registry, key}}
  end

  defp do_connect(state) do
    :telemetry.execute(
      [:hyperliquid, :ws, :connect, :start],
      %{system_time: System.system_time()},
      %{key: state.key}
    )

    uri = URI.parse(state.url)

    case transport_open(state, uri) do
      {:ok, conn} ->
        connect_timer = Process.send_after(self(), :connect_timeout, @connect_timeout)
        {:noreply, %{state | conn: conn, status: :opening, connect_timer: connect_timer}}

      {:error, reason} ->
        :telemetry.execute(
          [:hyperliquid, :ws, :connect, :exception],
          %{duration: 0},
          %{key: state.key, reason: reason}
        )

        Logger.warning("WebSocket connection failed (#{state.key}): #{inspect(reason)}")
        schedule_reconnect(state)
    end
  end

  defp transport_open(%State{transport: :gun}, uri) do
    opts = %{
      protocols: [:http],
      transport: if(uri.scheme in ["wss", "https"], do: :tls, else: :tcp),
      # Disable gun's built-in retry — we manage reconnection ourselves
      retry: 0,
      tls_opts: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 3,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    }

    :gun.open(String.to_charlist(uri.host), uri.port || 443, opts)
  end

  defp transport_open(%State{transport: mod}, uri), do: mod.open(uri)

  defp transport_ws_upgrade(%State{transport: :gun}, conn, path), do: :gun.ws_upgrade(conn, path)
  defp transport_ws_upgrade(%State{transport: mod}, conn, path), do: mod.ws_upgrade(conn, path)

  defp transport_send(%State{transport: :gun}, conn, stream_ref, frame),
    do: :gun.ws_send(conn, stream_ref, frame)

  defp transport_send(%State{transport: mod}, conn, stream_ref, frame),
    do: mod.ws_send(conn, stream_ref, frame)

  defp transport_close(%State{transport: :gun}, conn), do: :gun.close(conn)
  defp transport_close(%State{transport: mod}, conn), do: mod.close(conn)

  # ===================== Outbound pacing =====================

  # Every outbound subscribe/unsubscribe frame goes through a paced queue so
  # that a reconnect replaying hundreds of subscriptions cannot exceed the
  # per-IP message budget.
  defp enqueue(state, messages) do
    state = %{state | outbox: state.outbox ++ messages}

    if state.status == :connected do
      flush_outbox(state)
    else
      state
    end
  end

  defp flush_outbox(%State{outbox: []} = state), do: state

  defp flush_outbox(%State{status: status} = state) when status != :connected, do: state

  defp flush_outbox(state) do
    batch_size = Limits.resubscribe_batch_size()
    {batch, rest} = Enum.split(state.outbox, batch_size)

    case Budget.take_messages(length(batch)) do
      :ok ->
        Enum.each(batch, &send_message(state, &1))
        state = %{state | outbox: rest}

        if rest == [] do
          state
        else
          schedule_flush(state, Limits.resubscribe_batch_interval_ms())
        end

      {:error, {:rate_limited, retry_after}} ->
        schedule_flush(state, retry_after + :rand.uniform(50))
    end
  end

  defp schedule_flush(%State{flush_ref: ref} = state, _delay) when is_reference(ref), do: state

  defp schedule_flush(state, delay) do
    %{state | flush_ref: Process.send_after(self(), :flush_outbox, delay)}
  end

  defp send_message(%State{conn: conn, stream_ref: stream_ref} = state, message)
       when not is_nil(conn) and not is_nil(stream_ref) do
    case Jason.encode(message) do
      {:ok, json} ->
        transport_send(state, conn, stream_ref, {:text, json})
        :ok

      {:error, reason} ->
        {:error, {:json_encode, reason}}
    end
  end

  defp send_message(_state, _message), do: {:error, :not_connected}

  # ===================== Inbound =====================

  defp handle_ws_message(%{"channel" => "subscriptionResponse", "data" => data}, state) do
    pending_subscriptions =
      state.pending_subscriptions
      |> Enum.reject(fn {_id, req} -> matches_response?(req, data) end)
      |> Map.new()

    {:noreply, %{state | pending_subscriptions: pending_subscriptions}}
  end

  defp handle_ws_message(%{"channel" => "subscriptionResponse"}, state) do
    {:noreply, state}
  end

  defp handle_ws_message(%{"channel" => "error", "data" => error_msg} = message, state)
       when is_binary(error_msg) do
    if String.contains?(error_msg, "Already subscribed") do
      Logger.warning("WebSocket duplicate subscription from #{state.key}: #{error_msg}")
      {:noreply, %{state | pending_subscriptions: %{}}}
    else
      Logger.error("WebSocket error from #{state.key}: #{error_msg}")
      failed_sub_ids = Map.keys(state.pending_subscriptions)

      if state.manager && Process.alive?(state.manager) do
        send(state.manager, {:ws_error, self(), message, failed_sub_ids})
      end

      {:noreply, %{state | pending_subscriptions: %{}}}
    end
  end

  defp handle_ws_message(%{"channel" => "pong"}, state) do
    {:noreply, state}
  end

  defp handle_ws_message(%{"channel" => _channel} = message, state) do
    dispatch(message)
    {:noreply, state}
  end

  defp handle_ws_message(message, state) do
    Logger.debug("Unroutable WebSocket message on #{state.key}: #{inspect(message)}")
    {:noreply, state}
  end

  # Fan out to the subscribers whose full identity matches this frame. Only
  # `send/2` happens here — user code runs in the subscriber processes.
  defp dispatch(%{"channel" => channel} = message) do
    if registry_alive?() do
      Registry.dispatch(Hyperliquid.WebSocket.Dispatch, channel, fn entries ->
        Enum.each(entries, fn {pid, %{key: key}} ->
          if SubscriptionKey.matches?(key, message) do
            send(pid, {:hyperliquid_ws_frame, message})
          end
        end)
      end)
    end
  end

  defp registry_alive? do
    Process.whereis(Hyperliquid.WebSocket.Dispatch) != nil
  end

  defp handle_disconnect(%State{status: status} = state)
       when status in [:disconnected, :reconnecting] do
    # Already handling a disconnect — avoid duplicate reconnect scheduling
    {:noreply, state}
  end

  defp handle_disconnect(state) do
    :telemetry.execute([:hyperliquid, :ws, :disconnect], %{}, %{key: state.key})

    if state.heartbeat_ref, do: Process.cancel_timer(state.heartbeat_ref)
    if state.connect_timer, do: Process.cancel_timer(state.connect_timer)
    if state.conn, do: transport_close(state, state.conn)

    state = %{
      state
      | conn: nil,
        stream_ref: nil,
        status: :disconnected,
        heartbeat_ref: nil,
        connect_timer: nil,
        outbox: []
    }

    schedule_reconnect(state)
  end

  defp schedule_reconnect(state) do
    delay = backoff_delay(state.reconnect_attempts)

    Logger.info(
      "Scheduling reconnect for #{state.key} in #{delay}ms (attempt #{state.reconnect_attempts + 1})"
    )

    Process.send_after(self(), :reconnect, delay)

    {:noreply, %{state | reconnect_attempts: state.reconnect_attempts + 1, status: :reconnecting}}
  end

  # Replay every stored subscription, paced through the outbox.
  defp resubscribe_all(state) do
    requests =
      Enum.map(state.subscriptions, fn {_id, request} ->
        %{method: "subscribe", subscription: request}
      end)

    %{state | pending_subscriptions: state.subscriptions, outbox: requests}
    |> flush_outbox()
  end

  # Compare on string keys only. The response is server-controlled, so
  # `String.to_atom/1` here would let a novel key permanently consume an entry
  # in the (never garbage-collected) atom table.
  defp matches_response?(request, response) when is_map(response) do
    request = stringify_keys(request)

    if request["type"] != response["type"] do
      false
    else
      Enum.all?(response, fn {key, value} -> request[key] == value end)
    end
  end

  defp matches_response?(_request, _response), do: false

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp stringify_keys(other), do: other
end
