defmodule Hyperliquid.WebSocket.ConnectionTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Subscription.L2Book
  alias Hyperliquid.WebSocket.{Connection, SubscriptionKey}

  defmodule FakeTransport do
    @moduledoc false
    # A gun-shaped transport that never touches the network: `open/1` and
    # `ws_upgrade/2` post the gun messages the Connection expects back to the
    # calling (Connection) process, and every frame is mirrored to the test.

    def test_pid, do: Application.get_env(:hyperliquid, :fake_ws_test_pid)

    def open(_uri) do
      conn = make_ref()
      send(self(), {:gun_up, conn, :http})
      send(test_pid(), {:fake_open, conn})
      {:ok, conn}
    end

    def ws_upgrade(conn, path) do
      stream_ref = make_ref()
      send(self(), {:gun_upgrade, conn, stream_ref, ["websocket"], []})
      send(test_pid(), {:fake_upgrade, conn, path})
      stream_ref
    end

    def ws_send(conn, _stream_ref, {:text, json}) do
      send(test_pid(), {:fake_sent, conn, Jason.decode!(json)})
      :ok
    end

    def close(conn) do
      send(test_pid(), {:fake_close, conn})
      :ok
    end
  end

  setup do
    Application.put_env(:hyperliquid, :fake_ws_test_pid, self())
    on_exit(fn -> Application.delete_env(:hyperliquid, :fake_ws_test_pid) end)
    :ok
  end

  defp start_connection(key) do
    {:ok, pid} =
      Connection.start_link(
        key: key,
        manager: self(),
        url: "ws://fake.test/ws",
        transport: FakeTransport
      )

    assert_receive {:fake_open, conn}, 1_000
    assert_receive {:fake_upgrade, ^conn, "/ws"}, 1_000
    {pid, conn}
  end

  describe "connect and subscribe" do
    test "connects without blocking and never awaits the handshake" do
      {pid, _conn} = start_connection("test:conn:connect")

      assert %{status: :connected, subscriptions: 0} = Connection.status(pid)
    end

    test "subscribe is asynchronous and puts a frame on the wire" do
      {pid, conn} = start_connection("test:conn:sub")

      # A cast: it returns immediately even though the socket work is async.
      assert :ok = Connection.subscribe(pid, %{type: "l2Book", coin: "BTC"}, "s1")

      assert_receive {:fake_sent, ^conn,
                      %{"method" => "subscribe", "subscription" => %{"coin" => "BTC"}}},
                     1_000

      assert %{subscriptions: 1} = Connection.status(pid)

      assert :ok = Connection.unsubscribe(pid, "s1")
      assert_receive {:fake_sent, ^conn, %{"method" => "unsubscribe"}}, 1_000
      assert %{subscriptions: 0} = Connection.status(pid)
    end

    test "a slow manager cannot be blocked by the subscribe path" do
      {pid, _conn} = start_connection("test:conn:nonblocking")

      # 200 subscribes in a row must not block the caller anywhere near the old
      # 5s GenServer.call timeout.
      {micros, :ok} =
        :timer.tc(fn ->
          Enum.each(1..200, fn n ->
            Connection.subscribe(pid, %{type: "l2Book", coin: "C#{n}"}, "s#{n}")
          end)
        end)

      assert micros < 1_000_000
    end
  end

  describe "dispatch" do
    setup do
      {pid, conn} = start_connection("test:conn:dispatch")
      %{pid: pid, conn: conn}
    end

    test "frames only reach subscribers whose identity matches", %{pid: pid} do
      test_pid = self()

      btc = spawn_subscriber(test_pid, :btc, SubscriptionKey.routing_key(L2Book, %{coin: "BTC"}))
      eth = spawn_subscriber(test_pid, :eth, SubscriptionKey.routing_key(L2Book, %{coin: "ETH"}))

      assert_receive {:registered, :btc}
      assert_receive {:registered, :eth}

      send_frame(pid, %{"channel" => "l2Book", "data" => %{"coin" => "BTC", "levels" => []}})

      assert_receive {:got, :btc, %{"data" => %{"coin" => "BTC"}}}, 1_000
      refute_receive {:got, :eth, _}, 200

      send_frame(pid, %{"channel" => "l2Book", "data" => %{"coin" => "ETH", "levels" => []}})
      assert_receive {:got, :eth, %{"data" => %{"coin" => "ETH"}}}, 1_000
      refute_receive {:got, :btc, _}, 200

      Process.exit(btc, :kill)
      Process.exit(eth, :kill)
    end

    test "errors are reported to the manager with the pending subscription ids", %{
      pid: pid,
      conn: conn
    } do
      Connection.subscribe(pid, %{type: "l2Book", coin: "BTC"}, "s1")
      assert_receive {:fake_sent, ^conn, %{"method" => "subscribe"}}, 1_000

      send_frame(pid, %{"channel" => "error", "data" => "Something went wrong"})

      assert_receive {:ws_error, ^pid, %{"channel" => "error"}, ["s1"]}, 1_000
    end
  end

  describe "reconnect" do
    test "backoff grows exponentially, is capped and is jittered" do
      assert {500, 1_000} = Connection.backoff_range(0)
      assert {1_000, 2_000} = Connection.backoff_range(1)
      assert {2_000, 4_000} = Connection.backoff_range(2)
      assert {30_000, 60_000} = Connection.backoff_range(10)
      assert {30_000, 60_000} = Connection.backoff_range(100)

      for attempt <- 0..10 do
        {low, high} = Connection.backoff_range(attempt)
        delays = for _ <- 1..50, do: Connection.backoff_delay(attempt)

        assert Enum.all?(delays, &(&1 >= low and &1 <= high))
        # Jitter: not every socket redials at the same instant.
        if high > low, do: assert(length(Enum.uniq(delays)) > 1)
      end
    end

    test "a drop reconnects and replays every stored subscription" do
      {pid, conn} = start_connection("test:conn:reconnect")

      Connection.subscribe(pid, %{type: "l2Book", coin: "BTC"}, "s1")
      Connection.subscribe(pid, %{type: "trades", coin: "ETH"}, "s2")
      assert_receive {:fake_sent, ^conn, %{"method" => "subscribe"}}, 1_000
      assert_receive {:fake_sent, ^conn, %{"method" => "subscribe"}}, 1_000

      send(pid, {:gun_down, conn, :http, :closed, []})
      assert_receive {:fake_close, ^conn}, 1_000

      # Reconnects after the first backoff bucket (500-1000ms) ...
      assert_receive {:fake_open, new_conn}, 3_000
      assert_receive {:fake_upgrade, ^new_conn, _}, 1_000

      # ... and replays both subscriptions on the new socket.
      assert_receive {:fake_sent, ^new_conn, %{"method" => "subscribe", "subscription" => a}},
                     2_000

      assert_receive {:fake_sent, ^new_conn, %{"method" => "subscribe", "subscription" => b}},
                     2_000

      assert Enum.sort([a["coin"], b["coin"]]) == ["BTC", "ETH"]
      assert %{status: :connected, reconnect_attempts: 0} = Connection.status(pid)
    end

    test "an upgrade rejection keeps backing off instead of hammering once a second" do
      {pid, conn} = start_connection("test:conn:rejected")

      # TCP accepted, upgrade rejected (the shape of a connection-limit refusal).
      send(pid, {:gun_response, conn, make_ref(), :nofin, 429, []})
      assert_receive {:fake_close, ^conn}, 1_000

      %{reconnect_attempts: attempts} = Connection.status(pid)
      assert attempts >= 1
    end
  end

  # A stand-in subscriber: registers itself in the dispatch registry exactly the
  # way Hyperliquid.WebSocket.Subscriber does.
  defp spawn_subscriber(test_pid, tag, routing_key) do
    spawn(fn ->
      {:ok, _} =
        Registry.register(
          Hyperliquid.WebSocket.Dispatch,
          routing_key.channel,
          %{sub_id: "#{tag}", key: routing_key}
        )

      send(test_pid, {:registered, tag})
      loop(test_pid, tag)
    end)
  end

  defp loop(test_pid, tag) do
    receive do
      {:hyperliquid_ws_frame, message} ->
        send(test_pid, {:got, tag, message})
        loop(test_pid, tag)

      _ ->
        loop(test_pid, tag)
    end
  end

  defp send_frame(pid, message) do
    send(pid, {:gun_ws, nil, nil, {:text, Jason.encode!(message)}})
  end
end
