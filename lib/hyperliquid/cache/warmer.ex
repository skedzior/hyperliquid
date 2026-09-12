defmodule Hyperliquid.Cache.Warmer do
  @moduledoc """
  GenServer for async cache initialization with retry logic.

  Uses handle_continue/2 pattern for non-blocking startup - the supervision tree
  completes immediately while cache initialization happens in the background.

  ## Features

  - Non-blocking startup: Application starts immediately regardless of API availability
  - Honest partial failure: a partial warm-up is reported as `:partial`, not success
  - Automatic retry: failed *and partial* initialization retries with exponential backoff
  - Periodic refresh: metadata is re-fetched every `cache_refresh_interval` ms
  - Status introspection: check status via initialized?/0, warm_status/0 and status/0

  ## Usage

  The Warmer is started automatically by the supervision tree when autostart_cache is true.
  You can check its status:

      Hyperliquid.Cache.Warmer.initialized?()
      # => true   (only when EVERY source was fetched)

      Hyperliquid.Cache.Warmer.warm_status()
      # => :ok | :partial | :failed | :pending

      Hyperliquid.Cache.Warmer.status()
      # => %{warm_status: :partial, failed_keys: [:perp_dexs], retry_count: 1, ...}

  ## Behaviour note

  `initialized?/0` answers `true` only for a *complete* warm-up. A partially
  warmed cache answers `false` and keeps retrying; use `warm_status/0` if you
  want to accept degraded data.
  """

  use GenServer
  require Logger

  alias Hyperliquid.{Cache, Config}

  # ===================== Public API =====================

  @doc """
  Starts the Cache Warmer GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns whether the cache has been successfully initialized.

  ## Example

      Hyperliquid.Cache.Warmer.initialized?()
      # => true
  """
  def initialized?(timeout \\ 5_000) do
    GenServer.call(__MODULE__, :initialized?, timeout)
  end

  @doc """
  Returns the three-state warm-up status.

  - `:pending` - the first warm-up has not finished yet
  - `:ok` - every source was fetched
  - `:partial` - some sources failed; a retry is scheduled while attempts remain
  - `:failed` - nothing could be fetched and retries are exhausted
  """
  def warm_status(timeout \\ 5_000) do
    GenServer.call(__MODULE__, :warm_status, timeout)
  end

  @doc """
  Force an immediate metadata refresh (asynchronous).
  """
  def refresh do
    send(__MODULE__, :refresh_cache)
    :ok
  end

  @doc """
  Returns the full status of the warmer for debugging.

  ## Example

      Hyperliquid.Cache.Warmer.status()
      # => %{initialized: true, retry_count: 0, last_error: nil}
  """
  def status(timeout \\ 5_000) do
    GenServer.call(__MODULE__, :status, timeout)
  end

  # ===================== GenServer Callbacks =====================

  @impl true
  def init(_opts) do
    state = %{
      initialized: false,
      warm_status: :pending,
      failed_keys: [],
      retry_count: 0,
      last_error: nil,
      mids_subscription: nil,
      refresh_timer: nil
    }

    # Fast return - cache init happens in handle_continue
    {:ok, state, {:continue, :init_cache}}
  end

  @impl true
  def handle_continue(:init_cache, state) do
    case Cache.init_with_partial_success() do
      :ok ->
        Logger.info("[Cache.Warmer] Cache initialized successfully")

        {:noreply,
         %{
           state
           | initialized: true,
             warm_status: :ok,
             failed_keys: [],
             retry_count: 0,
             last_error: nil,
             mids_subscription: ensure_mids_subscription(state),
             refresh_timer: schedule_refresh(state)
         }}

      {:ok, :partial, failed_keys} ->
        Logger.warning(
          "[Cache.Warmer] Cache partially initialized, failed keys: #{inspect(failed_keys)}"
        )

        # A partial warm-up is NOT success: retry it with backoff, and report
        # :partial so callers can tell degraded data from complete data.
        state = %{
          state
          | initialized: false,
            warm_status: :partial,
            failed_keys: failed_keys,
            last_error: {:partial, failed_keys},
            mids_subscription: ensure_mids_subscription(state),
            refresh_timer: schedule_refresh(state)
        }

        {:noreply, maybe_retry(state, {:partial, failed_keys})}

      {:error, reason} = error ->
        Logger.warning(
          "[Cache.Warmer] Cache initialization failed",
          error: inspect(reason)
        )

        state = %{
          state
          | initialized: false,
            warm_status: :partial,
            last_error: error,
            refresh_timer: schedule_refresh(state)
        }

        {:noreply, maybe_retry(state, error)}
    end
  end

  # Retry with exponential backoff, bounded by cache_max_retries.
  defp maybe_retry(state, error) do
    retry_count = state.retry_count + 1
    max_retries = Config.cache_max_retries()

    if retry_count <= max_retries do
      delay = Config.cache_retry_delay() * round(:math.pow(2, retry_count - 1))

      Logger.info(
        "[Cache.Warmer] Retrying cache warm-up in #{delay}ms (#{retry_count}/#{max_retries})"
      )

      Process.send_after(self(), :retry, delay)
      %{state | retry_count: retry_count, last_error: error}
    else
      Logger.error(
        "[Cache.Warmer] Max retries (#{max_retries}) exceeded, running in degraded mode"
      )

      failed? = match?({:error, _}, error)

      %{
        state
        | retry_count: retry_count,
          last_error: error,
          warm_status: if(failed?, do: :failed, else: :partial)
      }
    end
  end

  @impl true
  def handle_info(:retry, state) do
    {:noreply, state, {:continue, :init_cache}}
  end

  # Periodic metadata refresh - picks up new listings / builder DEXs / decimals.
  def handle_info(:refresh_cache, state) do
    result = Cache.refresh()

    state =
      case result do
        :ok ->
          %{state | initialized: true, warm_status: :ok, failed_keys: [], last_error: nil}

        {:ok, :partial, failed_keys} ->
          Logger.warning("[Cache.Warmer] Cache refresh partially failed: #{inspect(failed_keys)}")

          %{state | warm_status: :partial, failed_keys: failed_keys}

        {:error, reason} ->
          Logger.warning("[Cache.Warmer] Cache refresh failed", error: inspect(reason))
          %{state | last_error: {:error, reason}}
      end

    {:noreply,
     %{
       state
       | mids_subscription: ensure_mids_subscription(state),
         refresh_timer: schedule_refresh(state)
     }}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:initialized?, _from, state) do
    {:reply, state.initialized, state}
  end

  def handle_call(:warm_status, _from, state) do
    {:reply, state.warm_status, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  # ===================== Private Helpers =====================

  # Re-subscribes if the socket died; keeps the existing id otherwise.
  defp ensure_mids_subscription(%{mids_subscription: nil}), do: subscribe_to_live_mids()
  defp ensure_mids_subscription(%{mids_subscription: sub_id}), do: sub_id

  defp schedule_refresh(state) do
    if state[:refresh_timer], do: Process.cancel_timer(state.refresh_timer)

    case Cache.refresh_interval() do
      interval when is_integer(interval) and interval > 0 ->
        Process.send_after(self(), :refresh_cache, interval)

      _ ->
        nil
    end
  end

  defp subscribe_to_live_mids do
    case Cache.subscribe_to_mids() do
      {:ok, sub_id} ->
        Logger.info("[Cache.Warmer] Subscribed to live mid price updates")
        sub_id

      {:error, reason} ->
        Logger.warning("[Cache.Warmer] Failed to subscribe to live mids", error: inspect(reason))
        nil
    end
  end
end
