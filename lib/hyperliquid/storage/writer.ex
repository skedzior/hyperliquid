defmodule Hyperliquid.Storage.Writer do
  @moduledoc """
  Writes subscription events to configured storage backends.

  Events are buffered and flushed periodically for efficiency. This GenServer
  provides both async (fire-and-forget) and sync (blocking) storage operations.

  ## Usage

      # Queue an event for async storage (recommended for high-throughput)
      Writer.store_async(Hyperliquid.Api.Subscription.Trades, event_data)

      # Store an event synchronously (for critical data)
      {:ok, :stored} = Writer.store_sync(module, event_data)

  ## Configuration

  The writer respects storage configuration defined in each subscription module
  via the `storage` option in `use Hyperliquid.Api.SubscriptionEndpoint`.

  ## Backpressure policy: bounded queues, drop-oldest

  `store_async/2` is a `cast`, so nothing upstream blocks. Two bounds keep the
  writer from turning a slow or locked Postgres into an unbounded mailbox:

  1. **At the caller** — `store_async/2` inspects the writer's mailbox length
     before casting. Above `config :hyperliquid, :storage_max_mailbox`
     (default 10_000) the event is dropped *at the source*, because a
     cast that has already been queued can no longer be dropped cheaply. This
     is the OOM guard.
  2. **In the server** — the buffer is capped at `:max_buffer` (default
     `buffer_size * 10`) and the retry set at `:max_pending_batches` (default 50). When either is full the **oldest**
     entries are discarded first, on the theory that market data is more useful
     fresh than complete.

  `store_async/2` also no longer raises when the writer is not running (i.e.
  `enable_db: false`); it counts the event as dropped and returns `:ok`.

  ## Retries

  A batch whose write fails is re-queued with exponential backoff
  (`:retry_base_backoff * 2^attempt`, capped at `:retry_max_backoff`, default 5 attempts). A batch that exhausts its attempts is
  dropped — loudly.

  ## Nothing is discarded silently

  Every drop and every failure emits telemetry, logs, and bumps a counter
  readable via `stats/0`:

  | event | measurements | metadata |
  | --- | --- | --- |
  | `[:hyperliquid, :storage, :flush, :stop]` | `record_count`, `duration`, `failed_batches` | |
  | `[:hyperliquid, :storage, :flush, :exception]` | `record_count` | `module`, `kind`, `reason` |
  | `[:hyperliquid, :storage, :write, :error]` | `record_count`, `attempt` | `module`, `reason` |
  | `[:hyperliquid, :storage, :retry]` | `record_count`, `attempt`, `backoff` | `module` |
  | `[:hyperliquid, :storage, :dropped]` | `count` | `module`, `reason` |

  `reason` on a drop is one of `:writer_not_running`, `:mailbox_full`,
  `:buffer_full`, `:pending_full`, `:retries_exhausted`.

  ## Testing

  The Ecto repo is resolved at write time from
  `config :hyperliquid, :storage_repo` (default `Hyperliquid.Repo`), so the
  write path can be unit-tested against a stub module that exports
  `insert_all/3` without a live Postgres.
  """

  use GenServer
  require Logger

  @type event_entry :: {module(), map(), integer()}

  defstruct [
    :buffer,
    :buffer_count,
    :timer_ref,
    :flush_interval,
    :buffer_size,
    :max_buffer,
    :max_mailbox,
    :max_pending_batches,
    :max_retries,
    :retry_base_backoff,
    :retry_max_backoff,
    :pending_batches,
    :stats
  ]

  # Default flush interval (5 seconds)
  @default_flush_interval 5_000

  # Default buffer size before forcing a flush
  @default_buffer_size 100

  # Hard cap on buffered events (drop-oldest beyond this)
  @default_max_buffer_factor 10

  # Hard cap on the writer mailbox; checked by the caller before casting
  @default_max_mailbox 10_000

  # Hard cap on batches awaiting retry
  @default_max_pending_batches 50

  # Retry policy
  @default_max_retries 5
  @default_retry_base_backoff 200
  @default_retry_max_backoff 30_000

  @empty_stats %{
    written: 0,
    dropped: 0,
    retried: 0,
    failed_batches: 0,
    flushes: 0
  }

  # ===================== Client API =====================

  @doc """
  Start the storage writer.

  ## Options

  - `:flush_interval` - Milliseconds between flushes (default: #{@default_flush_interval})
  - `:buffer_size` - Max events before forcing flush (default: #{@default_buffer_size})
  - `:max_buffer` - Hard cap on buffered events; oldest are dropped beyond it
    (default: `buffer_size * #{@default_max_buffer_factor}`)
  - `:max_mailbox` - Advisory mailbox cap; the caller-side check reads
    `config :hyperliquid, :storage_max_mailbox` (default: #{@default_max_mailbox})
  - `:max_pending_batches` - Cap on batches awaiting retry (default: #{@default_max_pending_batches})
  - `:max_retries` - Attempts before a failed batch is dropped (default: #{@default_max_retries})
  - `:retry_base_backoff` / `:retry_max_backoff` - Backoff bounds in ms
    (defaults: #{@default_retry_base_backoff} / #{@default_retry_max_backoff})
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Queue an event for async storage.

  Non-blocking and batched. Applies caller-side backpressure: if the writer is
  not running, or its mailbox is already over `:max_mailbox`, the event is
  dropped and accounted for (telemetry + log) rather than raising or growing
  the mailbox without bound. Always returns `:ok`.
  """
  @spec store_async(module(), map()) :: :ok
  def store_async(module, event_data) do
    case GenServer.whereis(__MODULE__) do
      nil ->
        drop(module, 1, :writer_not_running)

      pid ->
        if mailbox_over_limit?(pid) do
          drop(module, 1, :mailbox_full)
        else
          GenServer.cast(pid, {:store, module, event_data, System.monotonic_time()})
        end
    end
  end

  @doc """
  Counters for everything the writer has written, retried, failed or dropped.

  Returns `%{written: n, dropped: n, retried: n, failed_batches: n, flushes: n,
  buffer: n, pending_batches: n}`.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Store an event synchronously.

  This blocks until the event is written to all configured backends.
  """
  @spec store_sync(module(), map()) :: {:ok, :stored} | {:error, term()}
  def store_sync(module, event_data) do
    GenServer.call(__MODULE__, {:store_sync, module, event_data})
  end

  @doc """
  Force an immediate flush of the buffer.
  """
  @spec flush() :: :ok
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @doc """
  Get current buffer size.
  """
  @spec buffer_size() :: non_neg_integer()
  def buffer_size do
    GenServer.call(__MODULE__, :buffer_size)
  end

  # ===================== Server Callbacks =====================

  @impl true
  def init(opts) do
    flush_interval = Keyword.get(opts, :flush_interval, @default_flush_interval)
    buffer_size = Keyword.get(opts, :buffer_size, @default_buffer_size)
    timer_ref = schedule_flush(flush_interval)

    {:ok,
     %__MODULE__{
       buffer: [],
       buffer_count: 0,
       timer_ref: timer_ref,
       flush_interval: flush_interval,
       buffer_size: buffer_size,
       max_buffer: Keyword.get(opts, :max_buffer, buffer_size * @default_max_buffer_factor),
       max_mailbox: Keyword.get(opts, :max_mailbox, @default_max_mailbox),
       max_pending_batches: Keyword.get(opts, :max_pending_batches, @default_max_pending_batches),
       max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
       retry_base_backoff: Keyword.get(opts, :retry_base_backoff, @default_retry_base_backoff),
       retry_max_backoff: Keyword.get(opts, :retry_max_backoff, @default_retry_max_backoff),
       pending_batches: 0,
       stats: @empty_stats
     }}
  end

  @impl true
  def handle_cast({:store, module, event_data, timestamp}, state) do
    state =
      state
      |> push_buffer({module, event_data, timestamp})
      |> maybe_flush_full_buffer()

    {:noreply, state}
  end

  @impl true
  def handle_call({:store_sync, module, event_data}, _from, state) do
    result = write_to_storage(module, event_data)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {:reply, :ok, flush_buffer(state)}
  end

  @impl true
  def handle_call(:buffer_size, _from, state) do
    {:reply, state.buffer_count, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats =
      state.stats
      |> Map.put(:buffer, state.buffer_count)
      |> Map.put(:pending_batches, state.pending_batches)

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:flush, state) do
    state = flush_buffer(state)
    timer_ref = schedule_flush(state.flush_interval)
    {:noreply, %{state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_info({:retry, module, events, attempt}, state) do
    state = %{state | pending_batches: max(state.pending_batches - 1, 0)}

    case write_batch(module, events) do
      :ok ->
        {:noreply, bump(state, :written, length(events))}

      {:error, reason} ->
        {:noreply, handle_batch_failure(state, module, events, attempt, reason)}
    end
  end

  # ===================== Private Functions =====================

  defp schedule_flush(interval) do
    Process.send_after(self(), :flush, interval)
  end

  # --- buffer bookkeeping (drop-oldest when full) ---

  defp push_buffer(state, entry) do
    # Buffer is stored newest-first, so the oldest entries are at the tail.
    buffer = [entry | state.buffer]
    count = state.buffer_count + 1

    if count > state.max_buffer do
      overflow = count - state.max_buffer
      kept = Enum.take(buffer, state.max_buffer)
      dropped = Enum.drop(buffer, state.max_buffer)

      dropped
      |> Enum.group_by(fn {mod, _d, _ts} -> mod end)
      |> Enum.each(fn {mod, entries} -> drop(mod, length(entries), :buffer_full) end)

      %{state | buffer: kept, buffer_count: state.max_buffer}
      |> bump(:dropped, overflow)
    else
      %{state | buffer: buffer, buffer_count: count}
    end
  end

  defp maybe_flush_full_buffer(state) do
    if state.buffer_count >= state.buffer_size, do: flush_buffer(state), else: state
  end

  defp flush_buffer(%{buffer: []} = state), do: state

  defp flush_buffer(state) do
    buffer = state.buffer
    state = %{state | buffer: [], buffer_count: 0}
    do_flush(state, buffer)
  end

  defp do_flush(state, buffer) do
    start_time = System.monotonic_time()
    record_count = length(buffer)

    # Group by module for efficient batch operations
    batches =
      buffer
      |> Enum.reverse()
      |> Enum.group_by(fn {module, _data, _ts} -> module end)

    state =
      Enum.reduce(batches, state, fn {module, events}, acc ->
        case write_batch(module, events) do
          :ok ->
            bump(acc, :written, length(events))

          {:error, reason} ->
            handle_batch_failure(acc, module, events, 0, reason)
        end
      end)

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:hyperliquid, :storage, :flush, :stop],
      %{
        record_count: record_count,
        duration: duration,
        failed_batches: state.stats.failed_batches
      },
      %{}
    )

    bump(state, :flushes, 1)
  end

  # --- failure / retry handling ---

  defp handle_batch_failure(state, module, events, attempt, reason) do
    count = length(events)

    :telemetry.execute(
      [:hyperliquid, :storage, :write, :error],
      %{record_count: count, attempt: attempt},
      %{module: module, reason: reason}
    )

    state = bump(state, :failed_batches, 1)
    next_attempt = attempt + 1

    cond do
      next_attempt > state.max_retries ->
        Logger.error(
          "[Storage.Writer] Dropping #{count} record(s) for #{inspect(module)} after " <>
            "#{state.max_retries} failed attempts: #{inspect(reason)}"
        )

        drop(module, count, :retries_exhausted)
        bump(state, :dropped, count)

      state.pending_batches >= state.max_pending_batches ->
        Logger.error(
          "[Storage.Writer] Retry queue full (#{state.max_pending_batches}); dropping " <>
            "#{count} record(s) for #{inspect(module)}: #{inspect(reason)}"
        )

        drop(module, count, :pending_full)
        bump(state, :dropped, count)

      true ->
        backoff = retry_backoff(state, attempt)

        Logger.warning(
          "[Storage.Writer] Write failed for #{inspect(module)} (#{inspect(reason)}); " <>
            "retrying #{count} record(s) in #{backoff}ms (attempt #{next_attempt}/#{state.max_retries})"
        )

        :telemetry.execute(
          [:hyperliquid, :storage, :retry],
          %{record_count: count, attempt: next_attempt, backoff: backoff},
          %{module: module}
        )

        Process.send_after(self(), {:retry, module, events, next_attempt}, backoff)

        state
        |> Map.update!(:pending_batches, &(&1 + 1))
        |> bump(:retried, 1)
    end
  end

  defp retry_backoff(state, attempt) do
    min(state.retry_base_backoff * Bitwise.bsl(1, attempt), state.retry_max_backoff)
  end

  # --- counters / telemetry helpers ---

  defp bump(state, key, n) do
    %{state | stats: Map.update!(state.stats, key, &(&1 + n))}
  end

  defp drop(module, count, reason) do
    Logger.warning(
      "[Storage.Writer] Dropped #{count} event(s) for #{inspect(module)} (#{reason})"
    )

    :telemetry.execute(
      [:hyperliquid, :storage, :dropped],
      %{count: count},
      %{module: module, reason: reason}
    )

    :ok
  end

  defp mailbox_over_limit?(pid) do
    limit = Application.get_env(:hyperliquid, :storage_max_mailbox, @default_max_mailbox)

    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} -> len > limit
      nil -> false
    end
  end

  # Returns `:ok` or `{:error, reason}` — never swallows a failure.
  defp write_batch(module, events) do
    events_data = Enum.map(events, fn {_mod, data, _ts} -> data end)

    # Flatten if any event_data is itself a list (e.g., trades come as a list)
    flattened_data = flatten_event_data(events_data)

    # Check if module has storage config
    if storage_enabled?(module) do
      pg_result =
        if postgres_enabled?(module) do
          write_to_postgres(module, flattened_data)
        else
          {:ok, 0}
        end

      cache_result =
        if cache_enabled?(module) do
          flattened_data
          |> Enum.map(&write_to_cache(module, &1))
          |> Enum.find({:ok, 0}, &match?({:error, _}, &1))
        else
          {:ok, 0}
        end

      case Enum.find([pg_result, cache_result], &match?({:error, _}, &1)) do
        nil -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  rescue
    error ->
      Logger.error(
        "[Storage.Writer] Failed to write batch for #{inspect(module)}: #{Exception.message(error)}"
      )

      :telemetry.execute(
        [:hyperliquid, :storage, :flush, :exception],
        %{record_count: length(events)},
        %{module: module, kind: :error, reason: error}
      )

      {:error, error}
  end

  # Flatten event data - handles when events themselves are lists (like trades)
  defp flatten_event_data(events_data) do
    Enum.flat_map(events_data, fn
      data when is_list(data) -> data
      data -> [data]
    end)
  end

  defp write_to_storage(module, event_data) do
    results = []
    Logger.debug("[Storage.Writer] write_to_storage #{inspect(module)}")

    # Check if module has storage config
    unless storage_enabled?(module) do
      {:ok, :no_storage_configured}
    else
      results =
        if postgres_enabled?(module) do
          [{:postgres, write_to_postgres(module, [event_data])} | results]
        else
          results
        end

      results =
        if cache_enabled?(module) do
          [{:cache, write_to_cache(module, event_data)} | results]
        else
          results
        end

      case Enum.find(results, fn {_type, result} -> match?({:error, _}, result) end) do
        nil -> {:ok, :stored}
        {type, error} -> {:error, {type, error}}
      end
    end
  end

  # --- per-consumer storage overrides (M7) ---
  #
  # Each endpoint module declares its own storage policy in the DSL. That is a
  # library-author default, not a mandate: a consumer can override any of it at
  # runtime without recompiling the endpoint layer.
  #
  #     config :hyperliquid, :storage_overrides, %{
  #       Hyperliquid.Api.Subscription.Trades => false,        # persist nothing
  #       Hyperliquid.Api.Subscription.Bbo => [postgres: false] # cache only
  #     }
  #
  # `false` (or `[enabled: false]`) disables storage for that module entirely;
  # `:postgres` / `:cache` keys disable one backend.
  defp storage_enabled?(module) do
    case override(module) do
      false -> false
      opts -> Keyword.get(opts, :enabled, declared?(module, :storage_enabled?))
    end
  end

  defp postgres_enabled?(module) do
    case override(module) do
      false -> false
      opts -> Keyword.get(opts, :postgres, declared?(module, :postgres_enabled?))
    end
  end

  defp cache_enabled?(module) do
    case override(module) do
      false -> false
      opts -> Keyword.get(opts, :cache, declared?(module, :cache_enabled?))
    end
  end

  defp declared?(module, fun) do
    function_exported?(module, fun, 0) and apply(module, fun, [])
  end

  defp override(module) do
    case Application.get_env(:hyperliquid, :storage_overrides, %{}) do
      %{} = overrides ->
        case Map.get(overrides, module, []) do
          false -> false
          true -> []
          opts when is_list(opts) -> opts
          _ -> []
        end

      _ ->
        []
    end
  end

  # The repo is resolved at call time so tests can substitute a stub module
  # exporting `insert_all/3` (see `config :hyperliquid, :storage_repo`).
  defp repo do
    Application.get_env(:hyperliquid, :storage_repo, Hyperliquid.Repo)
  end

  defp repo_overridden? do
    Application.get_env(:hyperliquid, :storage_repo) not in [nil, Hyperliquid.Repo]
  end

  defp write_to_postgres(module, events_data) when is_list(events_data) do
    # Skip if database is not enabled (an explicit repo override wins)
    if Hyperliquid.Config.db_enabled?() or repo_overridden?() do
      do_write_to_postgres(module, events_data)
    else
      Logger.debug("[Storage.Writer] Skipping Postgres write - database not enabled")
      {:ok, 0}
    end
  end

  defp do_write_to_postgres(module, events_data) do
    Logger.debug("[Storage.Writer] write_to_postgres #{inspect(module)}")

    # Get all table configs (may be multiple)
    # All endpoints (Info and Subscription) now generate __postgres_tables__/0
    table_configs = module.__postgres_tables__()

    if table_configs == [] do
      {:error, :no_table_configured}
    else
      # Write to each table
      results =
        Enum.map(table_configs, fn config ->
          write_to_single_table(module, events_data, config)
        end)

      # Aggregate results
      case Enum.find(results, fn r -> match?({:error, _}, r) end) do
        nil ->
          total_count = Enum.sum(Enum.map(results, fn {:ok, count} -> count end))

          Logger.debug(
            "[Storage.Writer] Wrote #{total_count} total records across #{length(table_configs)} tables"
          )

          {:ok, total_count}

        error ->
          error
      end
    end
  end

  defp write_to_single_table(module, events_data, config) do
    table = config.table
    extract_field = config.extract
    transform_fn = config.transform

    Logger.debug("[Storage.Writer] write_to_single_table #{table}")

    # Extract records for this table
    records =
      cond do
        # Extract specific field from response
        extract_field && is_atom(extract_field) ->
          Enum.flat_map(events_data, fn event ->
            case event do
              %{^extract_field => recs} when is_list(recs) -> recs
              map when is_map(map) -> Map.get(map, extract_field, []) |> List.wrap()
              _ -> []
            end
          end)

        # No extraction configured but module has extract_records/1 - use it for normalization
        function_exported?(module, :extract_records, 1) ->
          Enum.flat_map(events_data, &module.extract_records/1)

        # No extraction - use whole event
        true ->
          events_data
      end

    if records == [] do
      {:ok, 0}
    else
      # Apply custom transformation if provided
      records =
        if transform_fn && is_function(transform_fn, 1) do
          try do
            transform_fn.(records)
          rescue
            error ->
              Logger.error(
                "[Storage.Writer] Transform failed for #{table}: #{Exception.message(error)}"
              )

              reraise error, __STACKTRACE__
          end
        else
          records
        end

      # Apply field filtering if configured
      filtered_records =
        if config.fields do
          Enum.map(records, fn record ->
            Enum.reduce(config.fields, %{}, fn field, acc ->
              value = Map.get(record, field) || Map.get(record, to_string(field))
              if value, do: Map.put(acc, field, value), else: acc
            end)
          end)
        else
          # Legacy: use module's extract_postgres_fields/1 if available
          if function_exported?(module, :extract_postgres_fields, 1) do
            Enum.map(records, &module.extract_postgres_fields/1)
          else
            records
          end
        end

      # Normalize and insert
      now = DateTime.utc_now()

      entries =
        Enum.map(filtered_records, fn record ->
          record
          |> normalize_record()
          |> Map.put(:inserted_at, now)
          |> maybe_add_updated_at(config, now)
        end)

      repo = repo()

      if Code.ensure_loaded?(repo) do
        try do
          insert_opts = build_insert_opts(config)
          {count, _} = apply(repo, :insert_all, [table, entries, insert_opts])
          Logger.debug("[Storage.Writer] Wrote #{count} records to #{table}")
          {:ok, count}
        rescue
          error ->
            Logger.error(
              "[Storage.Writer] Postgres insert failed for #{table}: #{Exception.message(error)}"
            )

            {:error, error}
        end
      else
        {:error, :repo_not_available}
      end
    end
  end

  # Add updated_at field if upsert is configured
  defp maybe_add_updated_at(record, config, now) do
    case config do
      %{on_conflict: {:replace, _fields}} ->
        Map.put(record, :updated_at, now)

      %{on_conflict: on_conflict} when on_conflict != :nothing ->
        Map.put(record, :updated_at, now)

      _ ->
        record
    end
  end

  # Build insert_all options based on config
  defp build_insert_opts(config) do
    case {config.conflict_target, config.on_conflict} do
      {nil, _} ->
        [on_conflict: :nothing, returning: false]

      {target, {:replace, fields}} ->
        [
          on_conflict: {:replace, fields},
          conflict_target: target,
          returning: false
        ]

      {target, on_conflict} ->
        [
          on_conflict: on_conflict,
          conflict_target: target,
          returning: false
        ]
    end
  end

  defp write_to_cache(module, event_data) do
    Logger.debug("[Storage.Writer] write_to_cache #{inspect(module)}")
    cache_key = module.build_cache_key(event_data)

    unless cache_key do
      {:ok, :no_key_pattern}
    else
      ttl = module.cache_ttl()

      # Apply field filtering if configured
      filtered_data =
        if function_exported?(module, :extract_cache_fields, 1) do
          module.extract_cache_fields(event_data)
        else
          event_data
        end

      Hyperliquid.Cache.put(cache_key, filtered_data)
      Logger.debug("[Storage.Writer] write_to_cache2 #{inspect(cache_key)}")

      if ttl do
        Cachex.expire(:hyperliquid, cache_key, ttl)
      end

      {:ok, cache_key}
    end
  rescue
    error ->
      Logger.error("[Storage.Writer] Cache write failed: #{Exception.message(error)}")
      {:error, error}
  end

  # Normalize a record for database insertion
  defp normalize_record(record) when is_struct(record) do
    record
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> normalize_record()
  end

  defp normalize_record(record) when is_map(record) do
    record
    # Transform special fields before processing
    |> transform_record()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {k, v} -> {to_safe_atom(k), v} end)
    |> Enum.reject(fn {k, _v} -> k == :__unknown__ end)
    |> Map.new()
  end

  # Transform record fields for storage compatibility
  # Handles: trades users array, explorer block camelCase fields, clearinghouse nested state
  defp transform_record(record) do
    record
    |> transform_users()
    |> transform_explorer_block()
    |> transform_clearinghouse()
  end

  # Transform users: [buyer, seller] into buyer/seller fields (for trades)
  defp transform_users(%{"users" => [buyer, seller]} = record) do
    record
    |> Map.put("buyer", buyer)
    |> Map.put("seller", seller)
    |> Map.delete("users")
  end

  defp transform_users(%{users: [buyer, seller]} = record) do
    record
    |> Map.put(:buyer, buyer)
    |> Map.put(:seller, seller)
    |> Map.delete(:users)
  end

  defp transform_users(record), do: record

  # Transform explorer block camelCase fields to snake_case
  defp transform_explorer_block(%{"blockTime" => block_time} = record) do
    record
    |> Map.put("time", block_time)
    |> Map.delete("blockTime")
    |> transform_num_txs()
  end

  defp transform_explorer_block(record), do: record

  defp transform_num_txs(%{"numTxs" => num_txs} = record) do
    record
    |> Map.put("num_txs", num_txs)
    |> Map.delete("numTxs")
  end

  defp transform_num_txs(record), do: record

  # Transform clearinghouseState nested object to flat fields
  defp transform_clearinghouse(%{"clearinghouseState" => state} = record) when is_map(state) do
    record
    |> Map.put("margin_summary", Map.get(state, "marginSummary"))
    |> Map.put("cross_margin_summary", Map.get(state, "crossMarginSummary"))
    |> Map.put("withdrawable", Map.get(state, "withdrawable"))
    |> Map.put("asset_positions", Map.get(state, "assetPositions"))
    |> Map.delete("clearinghouseState")
  end

  defp transform_clearinghouse(record), do: record

  # Convert string key to atom safely (only for known fields)
  defp to_safe_atom(key) when is_atom(key), do: key

  defp to_safe_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> :__unknown__
  end
end
