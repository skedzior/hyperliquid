defmodule Hyperliquid.NodeTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Node

  setup do
    bypass = Bypass.open()
    Application.put_env(:hyperliquid, :node_url, "http://localhost:#{bypass.port}")

    on_exit(fn ->
      Application.delete_env(:hyperliquid, :node_url)
    end)

    {:ok, bypass: bypass}
  end

  # ===================== Documented Endpoints =====================

  describe "no-param endpoints" do
    test "meta/0 sends correct payload and parses response", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "meta"

        resp = %{"universe" => [], "collateralToken" => 0}

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      assert {:ok, result} = Node.meta()
      # parse_response returns a struct
      assert is_struct(result)
    end

    test "exchange_status/0 sends correct payload", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "exchangeStatus"

        resp = %{"time" => 1_700_000_000_000, "specialStatuses" => %{}}

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      assert {:ok, _result} = Node.exchange_status()
    end

    test "spot_meta/0 sends correct payload", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "spotMeta"

        resp = %{"universe" => [], "tokens" => []}

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      assert {:ok, _result} = Node.spot_meta()
    end

    test "all_perp_metas/0 sends correct payload", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "allPerpMetas"

        resp = [%{"universe" => [], "marginTables" => [], "collateralToken" => 0}]

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      assert {:ok, _result} = Node.all_perp_metas()
    end

    test "all_borrow_lend_reserve_states/0 sends correct payload", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "allBorrowLendReserveStates"

        resp = [[0, %{"borrowYearlyRate" => "0.05", "supplyYearlyRate" => "0.01",
                       "balance" => "1000.0", "utilization" => "0.5",
                       "oraclePx" => "1.0", "ltv" => "0.9"}]]

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      assert {:ok, _result} = Node.all_borrow_lend_reserve_states()
    end

    test "spot_pair_deploy_auction_status/0 sends correct payload", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "spotPairDeployAuctionStatus"

        resp = %{
          "startTimeSeconds" => 1_700_000_000,
          "durationSeconds" => 111_600,
          "startGas" => "500.0",
          "currentGas" => "500.0",
          "endGas" => nil
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      assert {:ok, _result} = Node.spot_pair_deploy_auction_status()
    end
  end

  describe "user-param endpoints" do
    test "clearinghouse_state/1 sends user in payload", %{bypass: bypass} do
      user = "0xabcdef1234567890abcdef1234567890abcdef12"

      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "clearinghouseState"
        assert payload["user"] == user

        resp = %{
          "marginSummary" => %{
            "accountValue" => "1000.0",
            "totalNtlPos" => "0.0",
            "totalRawUsd" => "1000.0",
            "totalMarginUsed" => "0.0"
          },
          "crossMarginSummary" => %{
            "accountValue" => "1000.0",
            "totalNtlPos" => "0.0",
            "totalRawUsd" => "1000.0",
            "totalMarginUsed" => "0.0"
          },
          "crossMaintenanceMarginUsed" => "0.0",
          "withdrawable" => "1000.0",
          "assetPositions" => [],
          "time" => 1_700_000_000_000
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      assert {:ok, _result} = Node.clearinghouse_state(user)
    end

    test "open_orders/1 sends user in payload", %{bypass: bypass} do
      user = "0xabcdef1234567890abcdef1234567890abcdef12"

      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "openOrders"
        assert payload["user"] == user

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([]))
      end)

      assert {:ok, _result} = Node.open_orders(user)
    end

    test "sub_accounts2/1 sends user in payload", %{bypass: bypass} do
      user = "0xabcdef1234567890abcdef1234567890abcdef12"

      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "subAccounts2"
        assert payload["user"] == user

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([]))
      end)

      assert {:ok, _result} = Node.sub_accounts2(user)
    end

    test "user_dex_abstraction/1 sends user in payload", %{bypass: bypass} do
      user = "0xabcdef1234567890abcdef1234567890abcdef12"

      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "userDexAbstraction"
        assert payload["user"] == user

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(nil))
      end)

      assert {:ok, _result} = Node.user_dex_abstraction(user)
    end
  end

  describe "user+coin endpoints" do
    test "active_asset_data/2 sends user and coin in payload", %{bypass: bypass} do
      user = "0xabcdef1234567890abcdef1234567890abcdef12"
      coin = "BTC"

      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "activeAssetData"
        assert payload["user"] == user
        assert payload["coin"] == coin

        resp = %{
          "coin" => "BTC",
          "leverage" => %{"type" => "cross", "value" => 5},
          "maxTradeSzs" => ["1.0", "0.5"],
          "availableToTrade" => ["100.0", "50.0"],
          "markPx" => "45000.0"
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      assert {:ok, _result} = Node.active_asset_data(user, coin)
    end
  end

  describe "single-param endpoints" do
    test "margin_table/1 sends id in payload", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "marginTable"
        assert payload["id"] == 56

        resp = %{
          "description" => "tiered 40x",
          "marginTiers" => [%{"lowerBound" => "0.0", "maxLeverage" => 40}]
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      assert {:ok, _result} = Node.margin_table(56)
    end

    test "aligned_quote_token_info/1 sends token in payload", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "alignedQuoteTokenInfo"
        assert payload["token"] == 0

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(nil))
      end)

      assert {:ok, nil} = Node.aligned_quote_token_info(0)
    end

    test "perp_dex_limits/1 sends dex in payload", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "perpDexLimits"
        assert payload["dex"] == "hyperliquid"

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(nil))
      end)

      assert {:ok, _result} = Node.perp_dex_limits("hyperliquid")
    end
  end

  describe "web_data2 (nil endpoint module)" do
    test "web_data2/1 returns raw snake_cased map", %{bypass: bypass} do
      user = "0xabcdef1234567890abcdef1234567890abcdef12"

      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "webData2"
        assert payload["user"] == user

        resp = %{"clearinghouseState" => %{}, "openOrders" => []}

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      assert {:ok, result} = Node.web_data2(user)
      # nil endpoint module returns raw snake_cased map
      assert is_map(result)
      assert Map.has_key?(result, "clearinghouse_state")
    end
  end

  # ===================== Generic Fallback =====================

  describe "info_request/2" do
    test "sends arbitrary payload to node /info", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "someUndocumented"
        assert payload["customParam"] == "value"

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"result" => "ok"}))
      end)

      assert {:ok, %{"result" => "ok"}} =
               Node.info_request(%{type: "someUndocumented", customParam: "value"})
    end
  end

  # ===================== File Snapshots =====================

  describe "file_snapshot/3" do
    test "builds correct fileSnapshot payload", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "fileSnapshot"
        assert payload["request"] == %{"type" => "referrerStates"}
        assert payload["outPath"] == "/tmp/out.json"
        assert payload["includeHeightInOutput"] == false

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!("ok"))
      end)

      assert {:ok, "ok"} = Node.file_snapshot(%{type: "referrerStates"}, "/tmp/out.json")
    end

    test "passes include_height option", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["includeHeightInOutput"] == true

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!("ok"))
      end)

      assert {:ok, _} =
               Node.file_snapshot(%{type: "referrerStates"}, "/tmp/out.json", include_height: true)
    end
  end

  describe "referrer_states_snapshot/2" do
    test "delegates to file_snapshot with referrerStates request", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "fileSnapshot"
        assert payload["request"] == %{"type" => "referrerStates"}

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!("ok"))
      end)

      assert {:ok, _} = Node.referrer_states_snapshot("/tmp/referrer.json")
    end
  end

  describe "l4_snapshots/2" do
    test "builds correct l4Snapshots request with defaults", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "fileSnapshot"
        assert payload["request"]["type"] == "l4Snapshots"
        assert payload["request"]["includeUsers"] == true
        assert payload["request"]["includeTriggerOrders"] == true

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!("ok"))
      end)

      assert {:ok, _} = Node.l4_snapshots("/tmp/l4.json")
    end

    test "respects include_users and include_trigger_orders options", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["request"]["includeUsers"] == false
        assert payload["request"]["includeTriggerOrders"] == false

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!("ok"))
      end)

      assert {:ok, _} =
               Node.l4_snapshots("/tmp/l4.json",
                 include_users: false,
                 include_trigger_orders: false
               )
    end
  end

  # ===================== Ping =====================

  describe "ping/0" do
    test "sends exchangeStatus request to node", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["type"] == "exchangeStatus"

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"time" => 1_700_000_000_000}))
      end)

      assert {:ok, _} = Node.ping()
    end

    test "returns error when node is unreachable" do
      # Point to a port nothing is listening on
      Application.put_env(:hyperliquid, :node_url, "http://localhost:1")
      assert {:error, _} = Node.ping()
    end
  end

  # ===================== Error Handling =====================

  describe "error handling" do
    test "returns error on non-200 response", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/info", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{"error" => "internal"}))
      end)

      assert {:error, _} = Node.meta()
    end
  end

  # ===================== Config =====================

  describe "config" do
    test "node_url defaults to localhost:3001" do
      Application.delete_env(:hyperliquid, :node_url)
      assert Hyperliquid.Config.node_url() == "http://localhost:3001"
    end

    test "node_rpc_enabled? defaults to false" do
      Application.delete_env(:hyperliquid, :enable_node_rpc)
      refute Hyperliquid.Config.node_rpc_enabled?()
    end

    test "node_rpc_enabled? returns true when configured" do
      Application.put_env(:hyperliquid, :enable_node_rpc, true)
      assert Hyperliquid.Config.node_rpc_enabled?()
      Application.delete_env(:hyperliquid, :enable_node_rpc)
    end

    test "node_info_enabled? defaults to false" do
      Application.delete_env(:hyperliquid, :enable_node_info)
      refute Hyperliquid.Config.node_info_enabled?()
    end

    test "node_info_enabled? returns true when configured" do
      Application.put_env(:hyperliquid, :enable_node_info, true)
      assert Hyperliquid.Config.node_info_enabled?()
      Application.delete_env(:hyperliquid, :enable_node_info)
    end
  end
end
