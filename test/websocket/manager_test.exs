defmodule Hyperliquid.WebSocket.ManagerTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Subscription.{L2Book, OrderUpdates, UserFills}
  alias Hyperliquid.WebSocket.Manager

  defmodule FakeTransport do
    @moduledoc false
    # Same gun-shaped fake as the connection tests: no network, every frame is
    # mirrored to the test process.

    def test_pid, do: Application.get_env(:hyperliquid, :fake_mgr_test_pid)

    def open(_uri) do
      conn = make_ref()
      send(self(), {:gun_up, conn, :http})
      send(test_pid(), {:fake_open, self(), conn})
      {:ok, conn}
    end

    def ws_upgrade(conn, _path) do
      stream_ref = make_ref()
      send(self(), {:gun_upgrade, conn, stream_ref, ["websocket"], []})
      stream_ref
    end

    def ws_send(_conn, _stream_ref, {:text, json}) do
      send(test_pid(), {:fake_sent, self(), Jason.decode!(json)})
      :ok
    end

    def close(_conn), do: :ok
  end

  setup do
    Application.put_env(:hyperliquid, :fake_mgr_test_pid, self())
    Application.put_env(:hyperliquid, :ws_url, "ws://mgr.test/ws")

    table = :"ws_subs_#{System.unique_integer([:positive])}"
    conn_sup = :"conn_sup_#{System.unique_integer([:positive])}"
    sub_sup = :"sub_sup_#{System.unique_integer([:positive])}"
    manager = :"mgr_#{System.unique_integer([:positive])}"

    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: conn_sup})
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: sub_sup})

    start_supervised!(
      {Manager,
       name: manager,
       table: table,
       connection_supervisor: conn_sup,
       subscriber_supervisor: sub_sup,
       connection_opts: [transport: FakeTransport]}
    )

    on_exit(fn ->
      Application.delete_env(:hyperliquid, :fake_mgr_test_pid)
      Application.delete_env(:hyperliquid, :ws_url)
    end)

    %{manager: manager, conn_sup: conn_sup}
  end

  defp user(n), do: "0x" <> String.pad_leading("#{n}", 40, "0")

  describe "packing" do
    test "15 users share one connection, the 16th opens a second", %{manager: manager} do
      for n <- 1..16 do
        assert {:ok, _} = Manager.subscribe(UserFills, %{user: user(n)}, nil, manager)
      end

      info = Manager.connection_info(manager)

      assert info.total_subscriptions == 16
      assert info.total_connections == 2
      assert Enum.sort(Enum.map(info.connections, & &1.tracked_users)) == [1, 15]
    end

    test "market subscriptions never open extra connections", %{manager: manager} do
      for coin <- ~w(BTC ETH SOL AVAX DOGE) do
        assert {:ok, _} = Manager.subscribe(L2Book, %{coin: coin}, nil, manager)
      end

      info = Manager.connection_info(manager)
      assert info.total_connections == 1
      assert info.total_subscriptions == 5
    end

    test "several channels for one user stay on a single connection", %{manager: manager} do
      addr = user(1)

      assert {:ok, _} = Manager.subscribe(UserFills, %{user: addr}, nil, manager)
      assert {:ok, _} = Manager.subscribe(L2Book, %{coin: "BTC"}, nil, manager)

      assert {:ok, _} =
               Manager.subscribe(UserFills, %{user: addr, aggregateByTime: true}, nil, manager)

      info = Manager.connection_info(manager)
      assert info.total_connections == 1
      assert [%{tracked_users: 1, subscriptions: 3}] = info.connections
    end

    test "unattributed (group A) channels get one user per connection", %{manager: manager} do
      assert {:ok, _} = Manager.subscribe(OrderUpdates, %{user: user(1)}, nil, manager)
      assert {:ok, _} = Manager.subscribe(OrderUpdates, %{user: user(2)}, nil, manager)

      assert Manager.connection_info(manager).total_connections == 2
    end

    test "unsubscribing keeps the user's slot reserved for the linger window", %{
      manager: manager
    } do
      {:ok, id} = Manager.subscribe(UserFills, %{user: user(1)}, nil, manager)
      assert :ok = Manager.unsubscribe(id, manager)

      [conn] = Manager.connection_info(manager).connections
      assert conn.subscriptions == 0
      assert conn.tracked_users == 1
      assert conn.users == []
    end
  end

  describe "dispatch" do
    test "BTC and ETH l2Book subscribers do not receive each other's data", %{manager: manager} do
      test_pid = self()

      {:ok, btc} = Manager.subscribe(L2Book, %{coin: "BTC"}, nil, manager)

      {:ok, _eth} =
        Manager.subscribe(L2Book, %{coin: "ETH"}, &send(test_pid, {:eth, &1}), manager)

      conn_pid = connection_pid(manager)
      send_frame(conn_pid, %{"channel" => "l2Book", "data" => %{"coin" => "BTC", "levels" => []}})

      assert_receive {:hyperliquid_ws, ^btc, %{"data" => %{"coin" => "BTC"}}}, 1_000
      refute_receive {:eth, _}, 200

      send_frame(conn_pid, %{"channel" => "l2Book", "data" => %{"coin" => "ETH", "levels" => []}})
      assert_receive {:eth, %{"data" => %{"coin" => "ETH"}}}, 1_000
    end

    test "a raising callback does not affect other subscriptions", %{manager: manager} do
      test_pid = self()

      {:ok, _} = Manager.subscribe(L2Book, %{coin: "BTC"}, fn _ -> raise "boom" end, manager)
      {:ok, _} = Manager.subscribe(L2Book, %{coin: "ETH"}, &send(test_pid, {:eth, &1}), manager)

      conn_pid = connection_pid(manager)
      send_frame(conn_pid, %{"channel" => "l2Book", "data" => %{"coin" => "BTC"}})
      send_frame(conn_pid, %{"channel" => "l2Book", "data" => %{"coin" => "ETH"}})

      assert_receive {:eth, _}, 1_000
      assert Process.alive?(conn_pid)
      assert length(Manager.list_subscriptions(manager)) == 2
    end

    test "metrics are counted per subscription", %{manager: manager} do
      {:ok, btc} = Manager.subscribe(L2Book, %{coin: "BTC"}, nil, manager)
      {:ok, eth} = Manager.subscribe(L2Book, %{coin: "ETH"}, nil, manager)

      conn_pid = connection_pid(manager)
      send_frame(conn_pid, %{"channel" => "l2Book", "data" => %{"coin" => "BTC"}})
      assert_receive {:hyperliquid_ws, ^btc, _}, 1_000

      assert {:ok, %{message_count: 1}} = Manager.get_metrics(btc, manager)
      assert {:ok, %{message_count: 0}} = Manager.get_metrics(eth, manager)
    end
  end

  describe "crash resilience" do
    test "a connection crash does not orphan subscriptions — they are replayed", %{
      manager: manager
    } do
      {:ok, btc} = Manager.subscribe(L2Book, %{coin: "BTC"}, nil, manager)
      {:ok, _} = Manager.subscribe(UserFills, %{user: user(1)}, nil, manager)

      conn_pid = connection_pid(manager)
      assert_receive {:fake_open, ^conn_pid, _}, 1_000
      assert_receive {:fake_sent, ^conn_pid, %{"method" => "subscribe"}}, 1_000
      assert_receive {:fake_sent, ^conn_pid, %{"method" => "subscribe"}}, 1_000

      Process.exit(conn_pid, :kill)

      # The DynamicSupervisor restarts the socket and the Manager reattaches and
      # replays both subscriptions onto the new pid.
      assert_receive {:fake_open, new_pid, _conn}, 3_000
      assert new_pid != conn_pid

      assert_receive {:fake_sent, ^new_pid, %{"method" => "subscribe", "subscription" => a}},
                     3_000

      assert_receive {:fake_sent, ^new_pid, %{"method" => "subscribe", "subscription" => b}},
                     3_000

      assert Enum.sort([a["type"], b["type"]]) == ["l2Book", "userFills"]

      # Manager survived, subscriptions are intact and routed to the new socket.
      assert Process.alive?(Process.whereis(manager))
      assert length(Manager.list_subscriptions(manager)) == 2
      assert {:ok, sub} = Manager.get_subscription(btc, manager)
      assert sub.connection_pid == new_pid

      # ... and data still flows.
      send_frame(new_pid, %{"channel" => "l2Book", "data" => %{"coin" => "BTC"}})
      assert_receive {:hyperliquid_ws, ^btc, _}, 1_000
    end

    test "subscriptions die with the process that created them", %{manager: manager} do
      test_pid = self()

      owner =
        spawn(fn ->
          {:ok, id} = Manager.subscribe(L2Book, %{coin: "BTC"}, nil, manager)
          send(test_pid, {:subscribed, id})
          receive do: (:stop -> :ok)
        end)

      assert_receive {:subscribed, id}, 1_000
      assert length(Manager.list_subscriptions(manager)) == 1

      send(owner, :stop)

      wait_until(fn -> Manager.list_subscriptions(manager) == [] end)
      assert {:error, :not_found} = Manager.get_subscription(id, manager)

      # The capacity it held was released too.
      [conn] = Manager.connection_info(manager).connections
      assert conn.subscriptions == 0
    end
  end

  describe "limits" do
    test "the per-IP subscription cap is enforced", %{manager: manager} do
      Application.put_env(:hyperliquid, :ws_max_subscriptions_per_ip, 2)
      on_exit(fn -> Application.delete_env(:hyperliquid, :ws_max_subscriptions_per_ip) end)

      assert {:ok, _} = Manager.subscribe(L2Book, %{coin: "BTC"}, nil, manager)
      assert {:ok, _} = Manager.subscribe(L2Book, %{coin: "ETH"}, nil, manager)

      assert {:error, :subscription_limit_exceeded} =
               Manager.subscribe(L2Book, %{coin: "SOL"}, nil, manager)
    end

    test "the per-IP connection cap is enforced", %{manager: manager} do
      Application.put_env(:hyperliquid, :ws_max_users_per_connection, 1)
      Application.put_env(:hyperliquid, :ws_max_connections_per_ip, 2)

      on_exit(fn ->
        Application.delete_env(:hyperliquid, :ws_max_users_per_connection)
        Application.delete_env(:hyperliquid, :ws_max_connections_per_ip)
      end)

      assert {:ok, _} = Manager.subscribe(UserFills, %{user: user(1)}, nil, manager)
      assert {:ok, _} = Manager.subscribe(UserFills, %{user: user(2)}, nil, manager)

      assert {:error, :connection_limit_exceeded} =
               Manager.subscribe(UserFills, %{user: user(3)}, nil, manager)
    end
  end

  # ===================== helpers =====================

  defp connection_pid(manager) do
    [%{pid: pid} | _] = Manager.connection_info(manager).connections
    pid
  end

  defp send_frame(conn_pid, message) do
    send(conn_pid, {:gun_ws, nil, nil, {:text, Jason.encode!(message)}})
  end

  defp wait_until(fun, retries \\ 50) do
    cond do
      fun.() -> :ok
      retries == 0 -> flunk("condition never became true")
      true -> Process.sleep(20) && wait_until(fun, retries - 1)
    end
  end
end
