defmodule Hyperliquid.Streamer.Stream do
  use WebSockex
  require Logger

  import Hyperliquid.Utils
  alias Hyperliquid.Api.{Subscription, Explorer}
  alias Hyperliquid.Cache

  @ws_url Application.get_env(:hyperliquid, :ws_url)
  @heartbeat_interval 55_000
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
      @ws_url,
      __MODULE__,
      state, # debug: [:trace],
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

  def handle_cast({:add_sub, sub}, %{user: user, subs: subs} = state) do
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

  def handle_cast({:remove_sub, sub}, %{user: user, subs: subs} = state) do
    Subscription.to_encoded_message(sub, false)
    |> then(&{:reply, {:text, &1}, state})
  end

  @impl true
  def handle_disconnect(reason, %{restarts: restarts} = state) do
    IO.puts("Disconnected: #{inspect(reason)}")
    {:ok, state}
  end

  def handle_frame({:text, msg}, %{req_count: req_count, id: id} = state) do
    msg = Jason.decode!(msg, keys: :atoms)
    event = process_event(msg)

    new_state =
      case event.channel do
        "subscriptionResponse" -> update_active_subs(event, state)
        "post" -> state
        _ -> state
      end
      |> Map.merge(%{
        last_response: System.system_time(:second),
        req_count: req_count + 1
      })

    if event.channel == "allMids" do
      Cache.put(:all_mids, event.data.mids)
    end

    broadcast(event.channel, event)

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
    IO.inspect(event, label: "update_active_subs catchall")
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

  def process_event(%{channel: "post", data: %{id: id, response: response}} = msg) do
    %{
      id: id,
      channel: "post",
      subject: Subscription.get_subject(response.payload.type),
      data: response
    }
  end

  def process_event(%{channel: ch, data: data} = msg) do
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

  def process_event([%{height: block} = exp_block | _] = msg) do
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

  def terminate(close_reason, state) do
    IO.inspect({close_reason, state}, label: "Websocket terminated:")
  end

  defp via(state) do
    {:via, Registry, {@workers, state.id, state}}
  end
end
