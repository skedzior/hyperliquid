defmodule Hyperliquid.Api.PriorityAndRoutingTest do
  @moduledoc """
  Coverage for the gossip priority, USDC routing and perp annotation endpoints.
  """
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.GossipPriorityBid
  alias Hyperliquid.Api.Info.{GossipPriorityAuctionStatus, PerpConciseAnnotations, UsdcRouting}
  alias Hyperliquid.Api.Subscription.FastAssetCtxs

  @private_key "0x822e9959e022b78423eb653a62ea0020cd283e71a2a8133a6ff2aeffaf373cff"

  setup do
    bypass = Bypass.open()
    prev_url = Application.get_env(:hyperliquid, :http_url)
    Application.put_env(:hyperliquid, :http_url, "http://localhost:#{bypass.port}")

    on_exit(fn ->
      if prev_url,
        do: Application.put_env(:hyperliquid, :http_url, prev_url),
        else: Application.delete_env(:hyperliquid, :http_url)
    end)

    {:ok, bypass: bypass}
  end

  defp respond(bypass, path, capture_to, body) do
    Bypass.expect(bypass, "POST", path, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      if capture_to, do: send(capture_to, {:request, Jason.decode!(raw)})

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(body))
    end)
  end

  describe "usdcRouting" do
    test "parses both routes", %{bypass: bypass} do
      respond(bypass, "/info", self(), %{"depositRoute" => "cctp", "withdrawalRoute" => "bridge"})

      assert {:ok, routing} = UsdcRouting.request()

      assert_receive {:request, %{"type" => "usdcRouting"}}
      assert routing.deposit_route == "cctp"
      assert routing.withdrawal_route == "bridge"
      assert UsdcRouting.deposit_via_cctp?(routing)
      refute UsdcRouting.withdrawal_via_cctp?(routing)
    end

    test "routes/0 lists the known values" do
      assert UsdcRouting.routes() == ["bridge", "cctp"]
    end
  end

  describe "perpConciseAnnotations" do
    test "reshapes [coin, annotation] pairs", %{bypass: bypass} do
      respond(bypass, "/info", self(), [
        ["BTC", %{"category" => "major", "displayName" => "Bitcoin", "keywords" => ["btc"]}],
        ["ABC", %{"category" => "meme"}]
      ])

      assert {:ok, annotations} = PerpConciseAnnotations.request()

      assert_receive {:request, %{"type" => "perpConciseAnnotations"}}

      assert {:ok, btc} = PerpConciseAnnotations.find(annotations, "BTC")
      assert btc.category == "major"
      assert btc.display_name == "Bitcoin"
      assert btc.keywords == ["btc"]

      assert PerpConciseAnnotations.categories(annotations) == ["major", "meme"]
      assert PerpConciseAnnotations.by_category(annotations)["meme"] == ["ABC"]
      assert {:error, :not_found} = PerpConciseAnnotations.find(annotations, "NOPE")
    end

    test "skips malformed pairs", %{bypass: bypass} do
      respond(bypass, "/info", nil, [["BTC", %{"category" => "major"}], ["broken"], []])

      assert {:ok, annotations} = PerpConciseAnnotations.request()
      assert length(annotations.annotations) == 1
    end
  end

  describe "gossipPriorityAuctionStatus" do
    test "splits the two-element response", %{bypass: bypass} do
      respond(bypass, "/info", self(), [
        ["1.2.3.4", nil],
        [%{"startTimeSeconds" => 1, "durationSeconds" => 2}, %{"startTimeSeconds" => 3}]
      ])

      assert {:ok, status} = GossipPriorityAuctionStatus.request()

      assert_receive {:request, %{"type" => "gossipPriorityAuctionStatus"}}

      assert GossipPriorityAuctionStatus.slot_holders(status) == ["1.2.3.4", nil]
      refute GossipPriorityAuctionStatus.slot_available?(status, 0)
      assert GossipPriorityAuctionStatus.slot_available?(status, 1)

      assert {:ok, auction} = GossipPriorityAuctionStatus.auction_for(status, 0)
      assert auction["start_time_seconds"] == 1
      assert {:error, :not_found} = GossipPriorityAuctionStatus.auction_for(status, 9)
    end
  end

  describe "gossipPriorityBid" do
    test "sends slotId, ip and maxGas", %{bypass: bypass} do
      respond(bypass, "/exchange", self(), %{"status" => "ok"})

      assert {:ok, _} =
               GossipPriorityBid.request(0, "1.2.3.4", 1_000_000, private_key: @private_key)

      assert_receive {:request, request}
      action = request["action"]
      assert action["type"] == "gossipPriorityBid"
      assert action["slotId"] == 0
      assert action["ip"] == "1.2.3.4"
      assert action["maxGas"] == 1_000_000
    end

    test "accepts IPv6", %{bypass: bypass} do
      respond(bypass, "/exchange", self(), %{"status" => "ok"})

      assert {:ok, _} = GossipPriorityBid.request(1, "::1", 1, private_key: @private_key)
      assert_receive {:request, %{"action" => %{"ip" => "::1"}}}
    end

    test "rejects an out-of-range slot id" do
      assert_raise ArgumentError, ~r/slot_id must be between 0 and 1/, fn ->
        GossipPriorityBid.request(2, "1.2.3.4", 1, private_key: @private_key)
      end
    end

    test "rejects a malformed ip" do
      assert_raise ArgumentError, ~r/must be a valid IP address/, fn ->
        GossipPriorityBid.request(0, "not-an-ip", 1, private_key: @private_key)
      end
    end

    test "rejects negative max gas" do
      assert_raise ArgumentError, ~r/max_gas must be non-negative/, fn ->
        GossipPriorityBid.request(0, "1.2.3.4", -1, private_key: @private_key)
      end
    end
  end

  describe "fastAssetCtxs subscription" do
    test "builds a bare request" do
      assert {:ok, %{type: "fastAssetCtxs"}} = FastAssetCtxs.build_request(%{})
    end

    test "reads mark and mid prices" do
      event = %{ctxs: %{"BTC" => %{"markPx" => "50000", "midPx" => "50001"}, "ABC" => %{}}}

      assert {:ok, "50000"} = FastAssetCtxs.mark_px(event, "BTC")
      assert {:ok, "50001"} = FastAssetCtxs.mid_px(event, "BTC")
      assert {:error, :not_found} = FastAssetCtxs.mark_px(event, "ABC")
      assert {:error, :not_found} = FastAssetCtxs.mark_px(event, "MISSING")
      assert Enum.sort(FastAssetCtxs.coins(event)) == ["ABC", "BTC"]
    end

    test "treats an explicit null mid as absent" do
      event = %{ctxs: %{"BTC" => %{"markPx" => "50000", "midPx" => nil}}}

      assert {:ok, "50000"} = FastAssetCtxs.mark_px(event, "BTC")
      assert {:error, :not_found} = FastAssetCtxs.mid_px(event, "BTC")
    end

    test "preprocess nests a bare coin-keyed event" do
      assert %{ctxs: %{"BTC" => %{"markPx" => "1"}}} =
               FastAssetCtxs.preprocess(%{"BTC" => %{"markPx" => "1"}})
    end
  end
end
