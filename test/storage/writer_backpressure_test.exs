defmodule Hyperliquid.Storage.WriterBackpressureTest do
  @moduledoc """
  Backpressure, retry and accounting tests for `Hyperliquid.Storage.Writer`.

  These run against a stub repo module (`StubRepo` below) rather than Postgres,
  so they are part of the default offline suite — no `:requires_database` tag.
  """
  use ExUnit.Case, async: false

  alias Hyperliquid.Storage.Writer

  # ── Stub repo ────────────────────────────────────────────────────────────
  # Stands in for Hyperliquid.Repo. `insert_all/3` consults an agent so a test
  # can make the first N calls fail.

  defmodule StubRepo do
    def start(owner) do
      Agent.start_link(fn -> %{owner: owner, fail_next: 0, calls: 0} end, name: __MODULE__)
    end

    def fail_next(n) do
      Agent.update(__MODULE__, &%{&1 | fail_next: n})
    end

    def calls, do: Agent.get(__MODULE__, & &1.calls)

    def insert_all(table, entries, _opts) do
      action =
        Agent.get_and_update(__MODULE__, fn state ->
          state = %{state | calls: state.calls + 1}

          if state.fail_next > 0 do
            {{:fail, state.owner}, %{state | fail_next: state.fail_next - 1}}
          else
            {{:ok, state.owner}, state}
          end
        end)

      case action do
        {:fail, owner} ->
          send(owner, {:insert_all_failed, table, length(entries)})
          raise "stub insert_all failure"

        {:ok, owner} ->
          send(owner, {:insert_all, table, length(entries)})
          {length(entries), nil}
      end
    end
  end

  defmodule StubModule do
    def __postgres_tables__ do
      [
        %{
          table: "stub_table",
          extract: :records,
          conflict_target: nil,
          on_conflict: :nothing,
          transform: nil,
          fields: nil
        }
      ]
    end

    def storage_enabled?, do: true
    def postgres_enabled?, do: true
    def cache_enabled?, do: false
  end

  @telemetry_events [
    [:hyperliquid, :storage, :dropped],
    [:hyperliquid, :storage, :retry],
    [:hyperliquid, :storage, :write, :error],
    [:hyperliquid, :storage, :flush, :stop]
  ]

  setup do
    test_pid = self()
    start_supervised!(%{id: StubRepo, start: {StubRepo, :start, [test_pid]}})
    Application.put_env(:hyperliquid, :storage_repo, StubRepo)

    handler_id = {__MODULE__, System.unique_integer()}

    :telemetry.attach_many(
      handler_id,
      @telemetry_events,
      fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
      Application.delete_env(:hyperliquid, :storage_repo)
      Application.delete_env(:hyperliquid, :storage_max_mailbox)
    end)

    :ok
  end

  defp event(records), do: %{records: records}

  defp start_writer(opts) do
    start_supervised!({Writer, opts})
  end

  describe "store_async/2 when the writer is not running" do
    test "does not raise, and accounts for the dropped event" do
      refute GenServer.whereis(Writer)

      assert :ok = Writer.store_async(StubModule, event([%{id: 1}]))

      assert_receive {:telemetry, [:hyperliquid, :storage, :dropped], %{count: 1},
                      %{module: StubModule, reason: :writer_not_running}}
    end
  end

  describe "caller-side mailbox backpressure" do
    test "drops at the source once the mailbox is over the configured limit" do
      # A limit of -1 makes any mailbox length "over limit", which is the only
      # way to exercise the check deterministically without racing the server.
      start_writer(flush_interval: 60_000, buffer_size: 1_000)
      Application.put_env(:hyperliquid, :storage_max_mailbox, -1)

      assert :ok = Writer.store_async(StubModule, event([%{id: 1}]))

      assert_receive {:telemetry, [:hyperliquid, :storage, :dropped], %{count: 1},
                      %{module: StubModule, reason: :mailbox_full}}

      # Nothing reached the buffer.
      assert Writer.buffer_size() == 0
    end
  end

  describe "bounded buffer (drop-oldest)" do
    test "keeps the newest max_buffer events and reports the rest" do
      start_writer(flush_interval: 60_000, buffer_size: 1_000, max_buffer: 3)

      for i <- 1..5, do: Writer.store_async(StubModule, event([%{id: i}]))

      # Force the casts through.
      assert Writer.buffer_size() == 3

      assert_receive {:telemetry, [:hyperliquid, :storage, :dropped], %{count: 1},
                      %{reason: :buffer_full}}

      stats = Writer.stats()
      assert stats.dropped == 2
      assert stats.buffer == 3

      # The two oldest (ids 1 and 2) were the ones discarded.
      :ok = Writer.flush()
      assert_receive {:insert_all, "stub_table", 3}
    end
  end

  describe "retries with bounded backoff" do
    test "a failed batch is retried and eventually succeeds" do
      start_writer(
        flush_interval: 60_000,
        buffer_size: 1_000,
        retry_base_backoff: 1,
        retry_max_backoff: 5
      )

      StubRepo.fail_next(2)

      Writer.store_async(StubModule, event([%{id: 1}, %{id: 2}]))
      :ok = Writer.flush()

      assert_receive {:insert_all_failed, "stub_table", 2}

      assert_receive {:telemetry, [:hyperliquid, :storage, :write, :error], %{attempt: 0},
                      %{module: StubModule}}

      assert_receive {:telemetry, [:hyperliquid, :storage, :retry], %{attempt: 1, backoff: 1},
                      %{module: StubModule}}

      # Second attempt fails, third succeeds.
      assert_receive {:telemetry, [:hyperliquid, :storage, :retry], %{attempt: 2, backoff: 2}, _},
                     1_000

      assert_receive {:insert_all, "stub_table", 2}, 1_000

      assert StubRepo.calls() == 3
      stats = Writer.stats()
      assert stats.retried == 2
      # counters are in events (one store_async payload), not records
      assert stats.written == 1
      assert stats.dropped == 0
    end

    test "backoff is capped at retry_max_backoff" do
      start_writer(
        flush_interval: 60_000,
        buffer_size: 1_000,
        max_retries: 4,
        retry_base_backoff: 4,
        retry_max_backoff: 8
      )

      StubRepo.fail_next(10)

      Writer.store_async(StubModule, event([%{id: 1}]))
      :ok = Writer.flush()

      backoffs =
        for _ <- 1..4 do
          assert_receive {:telemetry, [:hyperliquid, :storage, :retry], %{backoff: backoff}, _},
                         1_000

          backoff
        end

      assert backoffs == [4, 8, 8, 8]
    end
  end

  describe "exhausted retries are never silent" do
    test "drops loudly with :retries_exhausted and counts the records" do
      start_writer(
        flush_interval: 60_000,
        buffer_size: 1_000,
        max_retries: 2,
        retry_base_backoff: 1,
        retry_max_backoff: 2
      )

      StubRepo.fail_next(100)

      Writer.store_async(StubModule, event([%{id: 1}, %{id: 2}]))
      :ok = Writer.flush()

      assert_receive {:telemetry, [:hyperliquid, :storage, :dropped], %{count: 1},
                      %{module: StubModule, reason: :retries_exhausted}},
                     1_000

      stats = Writer.stats()
      assert stats.dropped == 1
      assert stats.written == 0
      assert stats.pending_batches == 0
      # 1 initial attempt + 2 retries
      assert StubRepo.calls() == 3
    end
  end

  describe "retry queue is bounded" do
    test "drops with :pending_full rather than growing without bound" do
      start_writer(
        flush_interval: 60_000,
        buffer_size: 1_000,
        max_pending_batches: 1,
        # long enough that the first retry never fires during the test
        retry_base_backoff: 5_000,
        retry_max_backoff: 5_000
      )

      StubRepo.fail_next(100)

      Writer.store_async(StubModule, event([%{id: 1}]))
      :ok = Writer.flush()

      assert_receive {:telemetry, [:hyperliquid, :storage, :retry], _, _}

      Writer.store_async(StubModule, event([%{id: 2}]))
      :ok = Writer.flush()

      assert_receive {:telemetry, [:hyperliquid, :storage, :dropped], %{count: 1},
                      %{reason: :pending_full}}
    end
  end

  describe "happy path accounting" do
    test "successful flushes bump :written and emit flush telemetry" do
      start_writer(flush_interval: 60_000, buffer_size: 1_000)

      Writer.store_async(StubModule, event([%{id: 1}, %{id: 2}]))
      :ok = Writer.flush()

      assert_receive {:insert_all, "stub_table", 2}

      assert_receive {:telemetry, [:hyperliquid, :storage, :flush, :stop],
                      %{record_count: 1, failed_batches: 0}, _}

      stats = Writer.stats()
      assert stats.written == 1
      assert stats.dropped == 0
      assert stats.flushes == 1
    end
  end
end
