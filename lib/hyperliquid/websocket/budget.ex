defmodule Hyperliquid.WebSocket.Budget do
  @moduledoc """
  Process-wide (per-IP) budget for WebSocket connects and outbound frames.

  Hyperliquid's connection and message limits are per IP, so they cannot be
  enforced inside a single connection: a mass disconnect reconnects every socket
  at once and blows the 30-new-connections/minute budget, and every socket then
  replays its subscriptions and blows the ~100 messages/second budget.

  `Budget` is a shared token bucket over sliding windows. Connections ask before
  dialling and before replaying subscription batches, and back off with the
  returned `retry_after` when refused.

  Calls fail open (`:ok`) when the process is not running, so connections can be
  unit-tested without the supervision tree.
  """

  use GenServer

  alias Hyperliquid.WebSocket.Limits

  @type answer :: :ok | {:error, {:rate_limited, non_neg_integer()}}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Ask permission to open one new connection."
  @spec take_connection(GenServer.server()) :: answer()
  def take_connection(server \\ __MODULE__), do: safe_call(server, {:take, :connections, 1})

  @doc "Ask permission to send `n` outbound frames."
  @spec take_messages(pos_integer(), GenServer.server()) :: answer()
  def take_messages(n, server \\ __MODULE__), do: safe_call(server, {:take, :messages, n})

  @doc "Current window usage (for inspection/tests)."
  @spec usage(GenServer.server()) :: %{
          connections: non_neg_integer(),
          messages: non_neg_integer()
        }
  def usage(server \\ __MODULE__) do
    case safe_call(server, :usage) do
      %{} = usage -> usage
      _ -> %{connections: 0, messages: 0}
    end
  end

  @doc "Clear all windows (tests)."
  @spec reset(GenServer.server()) :: :ok
  def reset(server \\ __MODULE__) do
    safe_call(server, :reset)
    :ok
  end

  # ===================== Server =====================

  @impl true
  def init(_opts) do
    {:ok, %{connections: [], messages: []}}
  end

  @impl true
  def handle_call({:take, bucket, n}, _from, state) do
    now = System.monotonic_time(:millisecond)
    {window_ms, limit} = spec(bucket)

    recent = Enum.filter(Map.fetch!(state, bucket), &(&1 > now - window_ms))

    if length(recent) + n <= limit do
      stamps = List.duplicate(now, n) ++ recent
      {:reply, :ok, Map.put(state, bucket, stamps)}
    else
      retry_after =
        case Enum.min(recent, fn -> nil end) do
          nil -> window_ms
          oldest -> max(oldest + window_ms - now, 1)
        end

      {:reply, {:error, {:rate_limited, retry_after}}, Map.put(state, bucket, recent)}
    end
  end

  @impl true
  def handle_call(:usage, _from, state) do
    now = System.monotonic_time(:millisecond)

    usage =
      Map.new([:connections, :messages], fn bucket ->
        {window_ms, _limit} = spec(bucket)
        {bucket, Enum.count(Map.fetch!(state, bucket), &(&1 > now - window_ms))}
      end)

    {:reply, usage, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{connections: [], messages: []}}
  end

  defp spec(:connections), do: {60_000, Limits.max_connections_per_minute()}
  defp spec(:messages), do: {1_000, Limits.max_messages_per_second()}

  defp safe_call(server, message) do
    GenServer.call(server, message, 1_000)
  catch
    :exit, _ -> :ok
  end
end
