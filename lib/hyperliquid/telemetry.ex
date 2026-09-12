defmodule Hyperliquid.Telemetry do
  @moduledoc """
  Telemetry events emitted by Hyperliquid.

  ## API Events

  These events are emitted by the endpoint DSL for all Info and Exchange API calls:

  * `[:hyperliquid, :api, :request, :start]` — Info API request started
    * Measurements: `%{system_time: integer}`
    * Metadata: `%{module: module, endpoint: String.t(), request_type: String.t(), type: atom, params: map}`

  * `[:hyperliquid, :api, :request, :stop]` — Info API request completed
    * Measurements: `%{duration: native_time}`
    * Metadata: the `:start` metadata plus `%{result: :ok}`

  * `[:hyperliquid, :api, :request, :exception]` — Info API request failed
    * Measurements: `%{duration: native_time}`
    * Metadata: the `:start` metadata plus `%{result: :error, reason: term}`

  * `[:hyperliquid, :api, :exchange, :start]` — Exchange API request started
    * Measurements: `%{system_time: integer}`
    * Metadata: `%{module: module, endpoint: String.t(), action_type: String.t(), type: :exchange, signing: :l1 | :user_signed}`

  * `[:hyperliquid, :api, :exchange, :stop]` — Exchange API request completed
    * Measurements: `%{duration: native_time}`
    * Metadata: the `:start` metadata plus `%{result: :ok}`

  * `[:hyperliquid, :api, :exchange, :exception]` — Exchange API request failed
    * Measurements: `%{duration: native_time}`
    * Metadata: the `:start` metadata plus `%{result: :error, reason: term}`

  ## HTTP Transport Events

  Emitted by `Hyperliquid.Transport.Http` for every HTTP call, including calls
  made directly (e.g. by `Hyperliquid.Cache`) that bypass the endpoint DSL.
  Emitted via `:telemetry.span/3`, so a `:stop` or `:exception` always follows a
  `:start`.

  * `[:hyperliquid, :http, :request, :start]` — HTTP request started
    * Measurements: `%{system_time: integer, monotonic_time: integer}`
    * Metadata: `%{module: module, method: :get | :post, url: String.t(), request_type: :info | :exchange}`

  * `[:hyperliquid, :http, :request, :stop]` — HTTP request completed
    * Measurements: `%{duration: native_time, monotonic_time: integer}`
    * Metadata: `%{module: module, method: atom, url: String.t(), request_type: atom, result: :ok | :error, reason: term | nil}`

  * `[:hyperliquid, :http, :request, :exception]` — the request raised
    * Measurements: `%{duration: native_time, monotonic_time: integer}`
    * Metadata: `%{module: module, method: atom, url: String.t(), request_type: atom, kind: atom, reason: term, stacktrace: list}`

  ## WebSocket Events

  * `[:hyperliquid, :ws, :connect, :start]` — Connection attempt started
    * Measurements: `%{system_time: integer}`
    * Metadata: `%{key: String.t()}`

  * `[:hyperliquid, :ws, :connect, :stop]` — Connection established
    * Measurements: `%{duration: native_time}`
    * Metadata: `%{key: String.t()}`

  * `[:hyperliquid, :ws, :connect, :exception]` — Connection failed
    * Measurements: `%{duration: native_time}`
    * Metadata: `%{key: String.t(), reason: term}`

  * `[:hyperliquid, :ws, :message, :received]` — Message received
    * Measurements: `%{count: 1}`
    * Metadata: `%{key: String.t()}`

  * `[:hyperliquid, :ws, :disconnect]` — Connection lost
    * Measurements: `%{}`
    * Metadata: `%{key: String.t(), reason: term}`

  ## WebSocket Manager Events

  * `[:hyperliquid, :ws, :subscribe]` — Subscription created
    * Measurements: `%{count: 1}`
    * Metadata: `%{module: module, key: String.t()}`

  * `[:hyperliquid, :ws, :unsubscribe]` — Subscription removed
    * Measurements: `%{count: 1}`
    * Metadata: `%{subscription_id: String.t()}`

  ## Cache Events

  * `[:hyperliquid, :cache, :init, :stop]` — Cache initialization completed
    * Measurements: `%{duration: native_time}`
    * Metadata: `%{}`

  * `[:hyperliquid, :cache, :init, :exception]` — Cache initialization failed
    * Measurements: `%{duration: native_time}`
    * Metadata: `%{reason: term}`

  * `[:hyperliquid, :cache, :refresh, :stop]` — Cache refresh completed
    * Measurements: `%{duration: native_time}`
    * Metadata: `%{}`

  ## RPC Events

  * `[:hyperliquid, :rpc, :request, :start]` — RPC request started
    * Measurements: `%{system_time: integer}`
    * Metadata: `%{method: String.t()}`

  * `[:hyperliquid, :rpc, :request, :stop]` — RPC request completed
    * Measurements: `%{duration: native_time}`
    * Metadata: `%{method: String.t()}`

  * `[:hyperliquid, :rpc, :request, :exception]` — RPC request failed
    * Measurements: `%{duration: native_time}`
    * Metadata: `%{method: String.t(), reason: term}`

  ## Storage Events

  * `[:hyperliquid, :storage, :flush, :stop]` — Buffer flushed
    * Measurements: `%{record_count: integer, duration: native_time, failed_batches: integer}`
    * Metadata: `%{}`

  * `[:hyperliquid, :storage, :flush, :exception]` — a flush raised
    * Measurements: `%{record_count: integer}`
    * Metadata: `%{module: module, kind: atom, reason: term}`

  * `[:hyperliquid, :storage, :dropped]` — events dropped by backpressure
    * Measurements: `%{count: integer}`
    * Metadata: `%{module: module, reason: atom}` — `:writer_down`,
      `:mailbox_full`, `:buffer_full`, `:retries_exhausted`, `:retry_queue_full`

  * `[:hyperliquid, :storage, :retry]` — a failed batch is being retried
    * Measurements: `%{record_count: integer, attempt: integer, backoff: integer}`
    * Metadata: `%{module: module}`

  * `[:hyperliquid, :storage, :write, :error]` — a batch write failed
    * Measurements: `%{record_count: integer, attempt: integer}`
    * Metadata: `%{module: module, reason: term}`

  > `[:hyperliquid, :cache, :init, :stop]`, `[:hyperliquid, :cache, :refresh, :stop]`
  > and `[:hyperliquid, :storage, :flush, :stop]` are emitted without a matching
  > `:start`; they are one-shot completion events, not spans.

  ## Quick Setup

      Hyperliquid.Telemetry.attach_default_logger()

  ## Telemetry.Metrics Example

      defmodule MyApp.Telemetry do
        import Telemetry.Metrics

        def metrics do
          [
            summary("hyperliquid.api.request.stop.duration", unit: {:native, :millisecond}),
            summary("hyperliquid.api.exchange.stop.duration", unit: {:native, :millisecond}),
            counter("hyperliquid.ws.message.received.count"),
            summary("hyperliquid.rpc.request.stop.duration", unit: {:native, :millisecond}),
            last_value("hyperliquid.storage.flush.stop.record_count")
          ]
        end
      end
  """

  require Logger

  @doc """
  Attach a default logger that logs all Hyperliquid telemetry events at debug level.

  Useful for quick debugging. Returns `:ok`.
  """
  @spec attach_default_logger() :: :ok
  def attach_default_logger do
    events = [
      [:hyperliquid, :api, :request, :start],
      [:hyperliquid, :api, :request, :stop],
      [:hyperliquid, :api, :request, :exception],
      [:hyperliquid, :api, :exchange, :start],
      [:hyperliquid, :api, :exchange, :stop],
      [:hyperliquid, :api, :exchange, :exception],
      [:hyperliquid, :http, :request, :start],
      [:hyperliquid, :http, :request, :stop],
      [:hyperliquid, :http, :request, :exception],
      [:hyperliquid, :ws, :connect, :start],
      [:hyperliquid, :ws, :connect, :stop],
      [:hyperliquid, :ws, :connect, :exception],
      [:hyperliquid, :ws, :message, :received],
      [:hyperliquid, :ws, :disconnect],
      [:hyperliquid, :ws, :subscribe],
      [:hyperliquid, :ws, :unsubscribe],
      [:hyperliquid, :cache, :init, :stop],
      [:hyperliquid, :cache, :init, :exception],
      [:hyperliquid, :cache, :refresh, :stop],
      [:hyperliquid, :rpc, :request, :start],
      [:hyperliquid, :rpc, :request, :stop],
      [:hyperliquid, :rpc, :request, :exception],
      [:hyperliquid, :storage, :flush, :stop],
      [:hyperliquid, :storage, :flush, :exception],
      [:hyperliquid, :storage, :dropped],
      [:hyperliquid, :storage, :retry],
      [:hyperliquid, :storage, :write, :error]
    ]

    :telemetry.attach_many(
      "hyperliquid-default-logger",
      events,
      &__MODULE__.handle_event/4,
      :ok
    )

    :ok
  end

  @doc false
  def handle_event(event, measurements, metadata, _config) do
    Logger.debug(
      "[Hyperliquid.Telemetry] #{inspect(event)} #{inspect(measurements)} #{inspect(metadata)}"
    )
  end
end
