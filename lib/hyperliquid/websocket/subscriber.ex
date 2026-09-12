defmodule Hyperliquid.WebSocket.Subscriber do
  @moduledoc """
  One process per subscription: receives its frames and runs the consumer's
  callback.

  Previously every inbound frame was dispatched by the singleton Manager, which
  rebuilt its whole subscription map per message and invoked user callbacks
  *inline* — a slow or raising callback stalled or killed every feed for every
  consumer. Now:

    * `Hyperliquid.WebSocket.Connection` decodes a frame and fans it out with
      `Registry.dispatch/3` (matching on the full subscription identity, see
      `Hyperliquid.WebSocket.SubscriptionKey`) — sends only, no user code.
    * This process runs preprocessing, storage and the callback in its own
      process, so it can be slow, block or raise without affecting anything else.
    * It monitors the process that created the subscription and shuts down when
      that process dies, which auto-unsubscribes and frees the rate-limit slot.

  ## Delivery

  When a callback was given to `Hyperliquid.WebSocket.Manager.subscribe/3` it is
  invoked with the (preprocessed) message, exactly as before. When no callback is
  given, the message is forwarded to the owner process as:

      {:hyperliquid_ws, subscription_id, message}

  (previously such subscriptions received nothing at all).
  """

  use GenServer

  require Logger

  alias Hyperliquid.WebSocket.SubscriptionKey

  @metrics_table :ws_subscription_metrics
  @max_timestamps 60

  defstruct [:sub_id, :module, :params, :key, :routing_key, :callback, :owner, :owner_ref]

  @doc """
  Start a subscriber.

  Options: `:sub_id`, `:module`, `:params`, `:key` (a `SubscriptionKey`),
  `:callback` (or `nil`), `:owner` (pid to monitor and, absent a callback, to
  forward messages to).
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :sub_id)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      type: :worker
    }
  end

  @doc "Metrics accumulated for `sub_id`."
  @spec metrics(String.t()) :: %{
          message_count: non_neg_integer(),
          last_message_at: DateTime.t() | nil,
          message_timestamps: [DateTime.t()]
        }
  def metrics(sub_id) do
    case :ets.lookup(@metrics_table, sub_id) do
      [{^sub_id, count, last_at, timestamps}] ->
        %{message_count: count, last_message_at: last_at, message_timestamps: timestamps}

      _ ->
        %{message_count: 0, last_message_at: nil, message_timestamps: []}
    end
  end

  @doc "Drop metrics for `sub_id`."
  @spec forget(String.t()) :: :ok
  def forget(sub_id) do
    if :ets.whereis(@metrics_table) != :undefined, do: :ets.delete(@metrics_table, sub_id)
    :ok
  end

  # ===================== Server =====================

  @impl true
  def init(opts) do
    sub_id = Keyword.fetch!(opts, :sub_id)
    key = Keyword.fetch!(opts, :key)
    owner = Keyword.get(opts, :owner)

    routing_key = SubscriptionKey.to_routing_key(key)

    {:ok, _} =
      Registry.register(
        Hyperliquid.WebSocket.Dispatch,
        routing_key.channel,
        %{sub_id: sub_id, key: routing_key}
      )

    owner_ref = if is_pid(owner), do: Process.monitor(owner)

    state = %__MODULE__{
      sub_id: sub_id,
      module: Keyword.fetch!(opts, :module),
      params: Keyword.get(opts, :params, %{}),
      key: key,
      routing_key: routing_key,
      callback: Keyword.get(opts, :callback),
      owner: owner,
      owner_ref: owner_ref
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:hyperliquid_ws_frame, message}, state) do
    now = DateTime.utc_now()
    record_metrics(state.sub_id, now)

    message = maybe_preprocess(state.module, message)
    maybe_store_event(state.module, state.params, message)
    deliver(state, message)

    {:noreply, state}
  end

  def handle_info({:hyperliquid_ws_error, error_message}, state) do
    event = %{channel: "error", subscription_id: state.sub_id, error: error_message}
    deliver(state, event)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{owner_ref: ref} = state) do
    Logger.debug("Subscriber #{state.sub_id}: owner exited, stopping")
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    forget(state.sub_id)
    :ok
  end

  # ===================== Internals =====================

  defp deliver(%{callback: callback} = state, message) when is_function(callback, 1) do
    callback.(message)
  rescue
    error ->
      Logger.error(
        "Subscription callback for #{state.sub_id} raised: #{Exception.message(error)}"
      )
  catch
    kind, reason ->
      Logger.error("Subscription callback for #{state.sub_id} #{kind}: #{inspect(reason)}")
  end

  defp deliver(%{owner: owner, sub_id: sub_id}, message) when is_pid(owner) do
    send(owner, {:hyperliquid_ws, sub_id, message})
  end

  defp deliver(_state, _message), do: :ok

  defp record_metrics(sub_id, now) do
    if :ets.whereis(@metrics_table) != :undefined do
      {count, timestamps} =
        case :ets.lookup(@metrics_table, sub_id) do
          [{^sub_id, count, _last, timestamps}] -> {count, timestamps}
          _ -> {0, []}
        end

      :ets.insert(
        @metrics_table,
        {sub_id, count + 1, now, Enum.take([now | timestamps], @max_timestamps)}
      )
    end
  end

  # Subscription modules may define `preprocess/1` to transform the `data`
  # portion of an event before it is stored or handed to a callback.
  defp maybe_preprocess(module, %{"data" => data} = message) do
    Code.ensure_loaded(module)

    if function_exported?(module, :preprocess, 1) do
      Map.put(message, "data", module.preprocess(data))
    else
      message
    end
  end

  defp maybe_preprocess(_module, message), do: message

  defp maybe_store_event(module, params, message) do
    Code.ensure_loaded(module)

    if function_exported?(module, :storage_enabled?, 0) and module.storage_enabled?() do
      case extract_event_data(message) do
        nil ->
          :ok

        event_data ->
          event_data
          |> merge_subscription_context(params)
          |> then(&Hyperliquid.Storage.Writer.store_async(module, &1))
      end
    end
  rescue
    error ->
      Logger.warning(
        "[Subscriber] Storage failed for #{inspect(module)}: #{Exception.message(error)}"
      )
  end

  defp merge_subscription_context(event_data, nil), do: event_data

  defp merge_subscription_context(event_data, params) when map_size(params) == 0, do: event_data

  defp merge_subscription_context(event_data, params) when is_list(event_data) do
    Enum.map(event_data, fn
      item when is_map(item) -> Map.merge(params, item)
      item -> item
    end)
  end

  defp merge_subscription_context(event_data, params) when is_map(event_data) do
    Map.merge(params, event_data)
  end

  defp merge_subscription_context(event_data, _params), do: event_data

  defp extract_event_data(%{"data" => data}), do: data
  defp extract_event_data(%{data: data}), do: data
  defp extract_event_data(message) when is_list(message), do: message
  defp extract_event_data(message) when is_map(message), do: message
  defp extract_event_data(_), do: nil
end
