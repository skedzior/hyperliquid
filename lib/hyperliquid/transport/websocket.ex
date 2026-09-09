defmodule Hyperliquid.Transport.WebSocket do
  @moduledoc """
  WebSocket transport using Mint for Hyperliquid API.

  Features:
  - Mint-based WebSocket client
  - Automatic reconnection with exponential backoff
  - Proxy support (HTTP CONNECT tunneling)
  - Subscription management with callbacks
  - Automatic ping/pong handling
  - Message buffering during reconnection

  ## Usage

      # Start without proxy
      {:ok, pid} = WebSocket.start_link(url: "wss://api.hyperliquid.xyz/ws")

      # Start with proxy
      {:ok, pid} = WebSocket.start_link(
        url: "wss://api.hyperliquid.xyz/ws",
        proxy: %{host: "proxy.example.com", port: 8080},
        proxy_auth: {"username", "password"}
      )

      # Subscribe to a channel
      WebSocket.subscribe(pid, %{
        type: "webData2",
        user: "0x..."
      }, fn event ->
        IO.inspect(event, label: "WebData2 Event")
      end)

      # Unsubscribe
      WebSocket.unsubscribe(pid, subscription_id)
  """

  use GenServer
  require Logger

  alias __MODULE__.State

  # Default configuration
  @heartbeat_interval 50_000
  @timeout_seconds 60
  @max_reconnect_attempts 5
  @initial_reconnect_delay 1000
  @max_reconnect_delay 30_000

  # ===================== State =====================

  defmodule State do
    @moduledoc false

    defstruct [
      :url,
      :proxy,
      :proxy_auth,
      :conn,
      :websocket,
      :request_ref,
      :subscriptions,
      :pending_messages,
      :last_response_time,
      :reconnect_attempts,
      :reconnect_delay,
      :ping_timer,
      connected: false
    ]

    @type proxy_config :: %{host: String.t(), port: :inet.port_number()}
    @type proxy_auth :: {username :: String.t(), password :: String.t()}

    @type subscription :: %{
            id: reference(),
            channel: map(),
            callback: function()
          }

    @type t :: %__MODULE__{
            url: String.t(),
            proxy: proxy_config() | nil,
            proxy_auth: proxy_auth() | nil,
            conn: Mint.HTTP.t() | nil,
            websocket: Mint.WebSocket.t() | nil,
            request_ref: reference() | nil,
            subscriptions: %{reference() => subscription()},
            pending_messages: [binary()],
            last_response_time: integer(),
            reconnect_attempts: non_neg_integer(),
            reconnect_delay: pos_integer(),
            ping_timer: reference() | nil,
            connected: boolean()
          }
  end

  # ===================== Client API =====================

  @doc """
  Start the WebSocket client.

  ## Options

    * `:url` - WebSocket URL (required)
    * `:proxy` - Proxy configuration map with `:host` and `:port`
    * `:proxy_auth` - Tuple of `{username, password}` for proxy authentication
    * `:name` - Process name (optional)

  ## Examples

      {:ok, pid} = WebSocket.start_link(url: "wss://api.hyperliquid.xyz/ws")

      {:ok, pid} = WebSocket.start_link(
        url: "wss://api.hyperliquid.xyz/ws",
        proxy: %{host: "10.0.0.1", port: 8080},
        proxy_auth: {"user", "pass"}
      )
  """
  def start_link(opts) do
    {gen_opts, client_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, client_opts, gen_opts)
  end

  @doc """
  Subscribe to a channel with a callback.

  Returns `{:ok, subscription_id}` which can be used to unsubscribe later.

  ## Examples

      {:ok, sub_id} = WebSocket.subscribe(pid, %{
        type: "webData2",
        user: "0x1234..."
      }, fn event ->
        IO.inspect(event)
      end)
  """
  def subscribe(pid, channel, callback) when is_function(callback, 1) do
    GenServer.call(pid, {:subscribe, channel, callback})
  end

  @doc """
  Unsubscribe from a channel using the subscription ID.
  """
  def unsubscribe(pid, subscription_id) do
    GenServer.call(pid, {:unsubscribe, subscription_id})
  end

  @doc """
  Check if the WebSocket is currently connected.
  """
  def connected?(pid) do
    GenServer.call(pid, :connected?)
  end

  @doc """
  Get current connection statistics.
  """
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  # ===================== GenServer Callbacks =====================

  @impl true
  def init(opts) do
    url = Keyword.fetch!(opts, :url)
    proxy = Keyword.get(opts, :proxy)
    proxy_auth = Keyword.get(opts, :proxy_auth)

    state = %State{
      url: url,
      proxy: proxy,
      proxy_auth: proxy_auth,
      subscriptions: %{},
      pending_messages: [],
      last_response_time: System.system_time(:second),
      reconnect_attempts: 0,
      reconnect_delay: @initial_reconnect_delay
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case connect(state) do
      {:ok, new_state} ->
        Logger.info("WebSocket connected to #{state.url}")
        {:noreply, schedule_ping(new_state)}

      {:error, reason} ->
        Logger.error("Failed to connect: #{inspect(reason)}")
        {:noreply, schedule_reconnect(state)}
    end
  end

  @impl true
  def handle_call({:subscribe, channel, callback}, _from, state) do
    subscription_id = make_ref()

    subscription = %{
      id: subscription_id,
      channel: channel,
      callback: callback
    }

    new_state = %{
      state
      | subscriptions: Map.put(state.subscriptions, subscription_id, subscription)
    }

    # Send subscription message
    message = encode_subscription_message(channel, :subscribe)

    case send_message(new_state, message) do
      {:ok, updated_state} ->
        {:reply, {:ok, subscription_id}, updated_state}

      {:error, reason} ->
        # If not connected, queue the message
        if state.connected do
          {:reply, {:error, reason}, new_state}
        else
          queued_state = %{new_state | pending_messages: [message | new_state.pending_messages]}
          {:reply, {:ok, subscription_id}, queued_state}
        end
    end
  end

  @impl true
  def handle_call({:unsubscribe, subscription_id}, _from, state) do
    case Map.get(state.subscriptions, subscription_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      subscription ->
        message = encode_subscription_message(subscription.channel, :unsubscribe)
        new_state = %{state | subscriptions: Map.delete(state.subscriptions, subscription_id)}

        case send_message(new_state, message) do
          {:ok, updated_state} ->
            {:reply, :ok, updated_state}

          {:error, _reason} ->
            # Still remove from subscriptions even if send fails
            {:reply, :ok, new_state}
        end
    end
  end

  @impl true
  def handle_call(:connected?, _from, state) do
    {:reply, state.connected, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      connected: state.connected,
      subscriptions: map_size(state.subscriptions),
      pending_messages: length(state.pending_messages),
      reconnect_attempts: state.reconnect_attempts,
      last_response: state.last_response_time
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:send_ping, state) do
    age = System.system_time(:second) - state.last_response_time

    cond do
      age > @timeout_seconds ->
        Logger.warning("No response for #{@timeout_seconds}s, reconnecting...")
        {:noreply, do_reconnect(state)}

      state.connected ->
        ping_message = Jason.encode!(%{"method" => "ping"})

        case send_message(state, ping_message) do
          {:ok, new_state} ->
            {:noreply, schedule_ping(new_state)}

          {:error, _reason} ->
            {:noreply, do_reconnect(state)}
        end

      true ->
        {:noreply, schedule_ping(state)}
    end
  end

  @impl true
  def handle_info(:reconnect, state) do
    case connect(state) do
      {:ok, new_state} ->
        Logger.info("Reconnected successfully")
        # Reset the backoff only after a completed upgrade, not on TCP success.
        new_state = %{
          new_state
          | reconnect_attempts: 0,
            reconnect_delay: @initial_reconnect_delay
        }

        # Resubscribe to all channels
        final_state = resubscribe_all(new_state)
        {:noreply, schedule_ping(final_state)}

      {:error, reason} ->
        Logger.error("Reconnection failed: #{inspect(reason)}")

        if state.reconnect_attempts < @max_reconnect_attempts do
          {:noreply, schedule_reconnect(state)}
        else
          Logger.error("Max reconnection attempts reached, giving up")
          {:stop, :max_reconnections_reached, state}
        end
    end
  end

  @impl true
  def handle_info(message, state) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        new_state = %{state | conn: conn}
        handle_responses(new_state, responses)

      {:error, _conn, reason, _responses} ->
        Logger.error("WebSocket stream error: #{inspect(reason)}")
        {:noreply, do_reconnect(state)}

      :unknown ->
        {:noreply, state}
    end
  end

  # ===================== Private Functions =====================

  defp connect(state) do
    uri = URI.parse(state.url)

    http_scheme = if uri.scheme == "wss", do: :https, else: :http
    ws_scheme = if uri.scheme == "wss", do: :wss, else: :ws

    path = build_path(uri)

    with {:ok, conn} <- connect_http(http_scheme, uri, state),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(ws_scheme, conn, path, []),
         {:ok, conn, resp} <- receive_upgrade_response(conn, ref),
         {:ok, conn, websocket} <- finalize_websocket(conn, ref, resp) do
      new_state = %{
        state
        | conn: conn,
          websocket: websocket,
          request_ref: ref,
          connected: true,
          reconnect_attempts: 0,
          reconnect_delay: @initial_reconnect_delay,
          last_response_time: System.system_time(:second)
      }

      {:ok, new_state}
    else
      {:error, reason} -> {:error, reason}
      {:error, _conn, reason} -> {:error, reason}
    end
  end

  defp connect_http(http_scheme, uri, %{proxy: nil}) do
    Mint.HTTP.connect(http_scheme, uri.host, uri.port || default_port(http_scheme))
  end

  defp connect_http(http_scheme, uri, %{proxy: proxy, proxy_auth: proxy_auth}) do
    proxy_headers = build_proxy_headers(proxy_auth)
    proxy_config = {:http, proxy.host, proxy.port, proxy_headers}
    port = uri.port || default_port(http_scheme)

    Mint.TunnelProxy.connect(proxy_config, {http_scheme, uri.host, port, []})
  end

  defp build_proxy_headers(nil), do: []

  defp build_proxy_headers({username, password}) do
    credentials = Base.encode64("#{username}:#{password}")
    [{"proxy-authorization", "Basic #{credentials}"}]
  end

  defp default_port(:https), do: 443
  defp default_port(:http), do: 80

  defp build_path(%URI{path: path, query: nil}), do: path || "/"
  defp build_path(%URI{path: path, query: query}), do: "#{path || "/"}?#{query}"

  defp receive_upgrade_response(conn, ref) do
    receive do
      message ->
        case Mint.WebSocket.stream(conn, message) do
          {:ok, conn, [{:status, ^ref, status}, {:headers, ^ref, headers}, {:done, ^ref}]} ->
            {:ok, conn, %{status: status, headers: headers}}

          {:error, conn, reason, _responses} ->
            {:error, conn, reason}
        end
    after
      5000 -> {:error, :upgrade_timeout}
    end
  end

  defp finalize_websocket(conn, ref, resp) do
    case Mint.WebSocket.new(conn, ref, resp.status, resp.headers) do
      {:ok, conn, websocket} -> {:ok, conn, websocket}
      {:error, conn, reason} -> {:error, conn, reason}
    end
  end

  defp handle_responses(state, responses) do
    Enum.reduce(responses, {:ok, state}, fn response, acc ->
      case acc do
        {:ok, current_state} -> handle_response(current_state, response)
        error -> error
      end
    end)
    |> case do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, _reason} ->
        {:noreply, do_reconnect(state)}
    end
  end

  defp handle_response(state, {:data, _ref, data}) do
    case Mint.WebSocket.decode(state.websocket, data) do
      {:ok, websocket, frames} ->
        new_state = %{state | websocket: websocket}
        handle_frames(new_state, frames)

      {:error, _websocket, reason} ->
        Logger.error("Failed to decode frame: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_response(state, _response), do: {:ok, state}

  defp handle_frames(state, frames) do
    Enum.reduce(frames, {:ok, state}, fn frame, acc ->
      case acc do
        {:ok, current_state} -> handle_frame(current_state, frame)
        error -> error
      end
    end)
  end

  defp handle_frame(state, {:text, message}) do
    new_state = %{state | last_response_time: System.system_time(:second)}

    case Jason.decode(message) do
      {:ok, data} ->
        handle_message(new_state, data)
        {:ok, new_state}

      {:error, reason} ->
        Logger.warning("Failed to decode JSON: #{inspect(reason)}")
        {:ok, new_state}
    end
  end

  defp handle_frame(state, {:ping, data}) do
    case send_frame(state, {:pong, data}) do
      {:ok, new_state} -> {:ok, new_state}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_frame(state, {:pong, _data}) do
    {:ok, state}
  end

  defp handle_frame(_state, {:close, _code, _reason}) do
    Logger.info("WebSocket closed by server")
    {:error, :closed}
  end

  defp handle_frame(state, _frame), do: {:ok, state}

  defp handle_message(_state, %{"channel" => "pong"}) do
    # Pong response, nothing to do
    :ok
  end

  defp handle_message(_state, %{"channel" => "subscriptionResponse"}) do
    # Subscription confirmation, nothing to do
    :ok
  end

  defp handle_message(state, %{"channel" => channel, "data" => data} = message) do
    # Broadcast only to subscriptions whose full identity matches this frame
    # (channel + coin/user/interval/dex) — never on channel alone, or a BTC
    # l2Book subscriber would receive ETH books.
    Enum.each(state.subscriptions, fn {_id, sub} ->
      if matches_subscription?(sub.channel, channel, message) do
        try do
          sub.callback.(data)
        rescue
          error ->
            Logger.error("Subscription callback error: #{inspect(error)}")
        end
      end
    end)
  end

  defp handle_message(_state, data) do
    Logger.debug("Unhandled message: #{inspect(data)}")
  end

  defp matches_subscription?(sub_channel, _channel, message) do
    Hyperliquid.WebSocket.SubscriptionKey.matches_request?(sub_channel, message)
  end

  defp send_message(%{connected: false} = state, message) do
    # Queue message if not connected
    {:ok, %{state | pending_messages: [message | state.pending_messages]}}
  end

  defp send_message(state, message) do
    send_frame(state, {:text, message})
  end

  defp send_frame(state, frame) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(state.websocket, frame),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(state.conn, state.request_ref, data) do
      {:ok, %{state | conn: conn, websocket: websocket}}
    else
      {:error, %Mint.WebSocket{}, reason} -> {:error, reason}
      {:error, _conn, reason} -> {:error, reason}
    end
  end

  defp encode_subscription_message(channel, :subscribe) do
    Jason.encode!(%{
      "method" => "subscribe",
      "subscription" => channel
    })
  end

  defp encode_subscription_message(channel, :unsubscribe) do
    Jason.encode!(%{
      "method" => "unsubscribe",
      "subscription" => channel
    })
  end

  defp resubscribe_all(state) do
    # Send all pending messages first
    state_after_pending =
      Enum.reduce(Enum.reverse(state.pending_messages), state, fn message, acc ->
        case send_message(acc, message) do
          {:ok, new_state} -> new_state
          {:error, _} -> acc
        end
      end)

    # Resubscribe to all channels
    Enum.reduce(state_after_pending.subscriptions, state_after_pending, fn {_id, sub}, acc ->
      message = encode_subscription_message(sub.channel, :subscribe)

      case send_message(acc, message) do
        {:ok, new_state} -> new_state
        {:error, _} -> acc
      end
    end)
    |> Map.put(:pending_messages, [])
  end

  defp schedule_ping(state) do
    if state.ping_timer, do: Process.cancel_timer(state.ping_timer)
    timer = Process.send_after(self(), :send_ping, @heartbeat_interval)
    %{state | ping_timer: timer}
  end

  defp schedule_reconnect(state) do
    new_attempts = state.reconnect_attempts + 1
    ceiling = min(state.reconnect_delay * 2, @max_reconnect_delay)
    # Jitter over the lower half of the bucket so that sockets which dropped
    # together do not all redial at the same instant and storm the per-IP
    # new-connection budget.
    delay = div(ceiling, 2) + :rand.uniform(div(ceiling, 2) + 1) - 1

    Logger.info("Scheduling reconnect attempt #{new_attempts} in #{delay}ms")
    Process.send_after(self(), :reconnect, delay)

    %{state | reconnect_attempts: new_attempts, reconnect_delay: ceiling, connected: false}
  end

  defp do_reconnect(state) do
    # Close existing connection if any
    if state.conn do
      Mint.HTTP.close(state.conn)
    end

    schedule_reconnect(%{state | conn: nil, websocket: nil, request_ref: nil, connected: false})
  end
end
