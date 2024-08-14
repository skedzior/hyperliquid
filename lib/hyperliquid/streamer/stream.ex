defmodule Hyperliquid.Streamer.Stream do
  @moduledoc """
  WebSocket client for streaming data from the Hyperliquid API.

  This module implements a WebSocket client that connects to the Hyperliquid API,
  manages subscriptions, and processes incoming data. It handles connection
  management, subscription requests, heartbeats, and message processing.

  ## Key Features

  - Establishes and maintains WebSocket connections
  - Manages user and non-user subscriptions
  - Handles heartbeats and connection timeouts
  - Processes and broadcasts incoming messages
  - Supports dynamic subscription management

  ## Usage

  This module is used to subscribe to ws events and can also support post requests.
  Typically this module shouldn't be called directly, as it is meant to be managed by the
  Manager, errors may occur when used outside that context.

  To subscribe to the broadcasts of ws events, you can refer to the subscription `type` for the
  channel value to subscribe to in your own application.

  Example:

      # Start a new stream with initial subscriptions
      {:ok, pid} = Hyperliquid.Streamer.Stream.start_link([%{type: "allMids"}])

      # Add a new subscription
      Hyperliquid.Streamer.Stream.subscribe(pid, %{type: "trades", coin: "BTC"})

      # Remove a subscription
      Hyperliquid.Streamer.Stream.unsubscribe(pid, %{type: "trades", coin: "BTC"})
  """
  use WebSockex
  require Logger

  import Hyperliquid.Utils
  alias Hyperliquid.{Api.Subscription, Cache, Config, PubSub}

  @heartbeat_interval 50_000
  @timeout_seconds 60

  @workers :worker_registry
  @users :user_registry

  @ping Jason.encode!(%{"method" => "ping"})

  def start_link(subs \\ []) do
    state = %{
      id: make_cloid(),
      user: nil,
      subs: subs,
      req_count: 0,
      active_subs: 0,
      last_response: System.system_time(:second)
    }

    WebSockex.start_link(
      Config.ws_url(),
      __MODULE__,
      state,
      name: via(state)
    )
  end

  def post(pid, type, payload) do
    WebSockex.send_frame(pid, {:text,
      Jason.encode!(%{
        method: "post",
        id: Cache.increment(),
        request: %{
          type: type,
          payload: payload
        }
      })
    })
  end

  def subscribe(pid, sub) do
    WebSockex.cast(pid, {:add_sub, sub})
  end

  def unsubscribe(pid, sub) do
    WebSockex.cast(pid, {:remove_sub, sub})
  end

  @impl true
  def handle_connect(_conn, state) do
    :timer.send_interval(@heartbeat_interval, self(), :send_ping)

    Enum.each(state.subs, &WebSockex.cast(self(), {:add_sub, &1}))

    {:ok, %{state | subs: []}}
  end

  @impl true
  def handle_info(:send_ping, state) do
    age = System.system_time(:second) - state.last_response

    if age > @timeout_seconds do
      Logger.warning("No response for over #{@timeout_seconds} seconds. Restarting Websocket process.")
      {:close, state}
    else
      {:reply, {:text, @ping}, state}
    end
  end

  @impl true
  def handle_cast({:add_sub, sub}, %{user: user} = state) do
    message = Subscription.to_encoded_message(sub)
    subject = Subscription.get_subject(sub)

    cond do
      subject == :user && is_nil(user) ->
        new_user = Map.get(sub, :user) |> String.downcase()
        Registry.register(@users, new_user, [])
        {:reply, {:text, message}, %{state | user: new_user}}

      subject == :user && user != String.downcase(sub.user) ->
        {:ok, state}

      true ->
        {:reply, {:text, message}, state}
    end
  end

  @impl true
  def handle_cast({:remove_sub, sub}, state) do
    Subscription.to_encoded_message(sub, false)
    |> then(&{:reply, {:text, &1}, state})
  end

  @impl true
  def handle_disconnect(reason, state) do
    IO.puts("Disconnected: #{inspect(reason)}")
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, msg}, %{req_count: req_count, id: id} = state) do
    msg = Jason.decode!(msg, keys: :atoms)
    event = process_event(msg)

    new_state =
      case event.channel do
        "subscriptionResponse" ->
          update_active_subs(event, state)

        "allMids" ->
          Cache.put(:all_mids, event.data.mids)
          state

        _ ->
          state
      end
      |> Map.merge(%{
        last_response: System.system_time(:second),
        req_count: req_count + 1
      })

    broadcast("ws_event", Map.merge(event, %{
      pid: self(),
      wid: id,
      subs: state.subs
    }))

    Registry.update_value(@workers, id, fn _ -> new_state end)

    {:ok, new_state}
  end

  defp update_active_subs(%{data: %{method: method, subscription: sub}}, %{subs: subs} = state) do
    new_subs =
      case method do
        "subscribe" -> [sub | subs]
        "unsubscribe" -> Enum.reject(subs, &(&1 == sub))
        _ -> subs
      end

    user =
      new_subs
      |> Enum.any?(&Map.has_key?(&1, :user))
      |> case do
        true ->
          Registry.update_value(@users, state.user, fn _ -> new_subs end)
          state.user
        false ->
          Registry.unregister(@users, state.user)
          nil
      end

    new_state = %{state |
      user: user,
      subs: new_subs,
      active_subs: Enum.count(new_subs)
    }

    Registry.update_value(@workers, state.id, fn _ -> new_state end)

    new_state
  end

  defp update_active_subs(event, state) do
    Logger.warning("Update active subs catchall: #{inspect(event)}")
    state
  end

  def process_event(%{channel: ch, data: %{subscription: sub, method: method} = data}) do
    %{
      channel: ch,
      subject: Subscription.get_subject(sub),
      data: data,
      method: method,
      sub: sub,
      key: Subscription.to_key(sub)
    }
  end

  def process_event(%{channel: "post", data: %{id: id, response: response}}) do
    %{
      id: id,
      channel: "post",
      subject: Subscription.get_subject(response.payload.type),
      data: response
    }
  end

  def process_event(%{channel: ch, data: data}) do
    %{
      channel: ch,
      subject: Subscription.get_subject(ch),
      data: data
    }
  end

  def process_event([%{action: _} | _] = msg) do
    %{
      channel: "explorerTxs",
      subject: :txs,
      data: msg
    }
  end

  def process_event([%{height: _} | _] = msg) do
    %{
      channel: "explorerBlock",
      subject: :block,
      data: msg
    }
  end

  def process_event(msg) do
    %{
      channel: nil,
      subject: nil,
      data: msg
    }
  end

  defp broadcast(channel, event) do
    Phoenix.PubSub.broadcast(PubSub, channel, event)
  end

  @impl true
  def terminate(close_reason, _state) do
    Logger.warning("Websocket terminated: #{inspect(close_reason)}")
  end

  defp via(state) do
    {:via, Registry, {@workers, state.id, state}}
  end
end
