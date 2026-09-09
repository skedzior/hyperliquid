defmodule Hyperliquid.WebSocket.SubscriptionKeyTest do
  use ExUnit.Case, async: true

  alias Hyperliquid.Api.Subscription.{AllMids, Candle, L2Book, OrderUpdates, Trades, UserFills}
  alias Hyperliquid.WebSocket.SubscriptionKey

  defp frame(channel, data), do: %{"channel" => channel, "data" => data}

  describe "identity" do
    test "includes non-echoed key fields, routing key does not" do
      identity = SubscriptionKey.identity(L2Book, %{coin: "BTC", nSigFigs: 5})

      assert identity.channel == "l2Book"
      assert identity.fields[:coin] == "BTC"
      assert identity.fields[:nSigFigs] == "5"
      assert SubscriptionKey.to_string(identity) == "l2Book|coin=BTC,nSigFigs=5"

      routing = SubscriptionKey.to_routing_key(identity)
      assert routing.fields == %{coin: "BTC"}
      assert SubscriptionKey.to_string(routing) == "l2Book|coin=BTC"
    end

    test "same?/2 distinguishes parameter variants" do
      a = SubscriptionKey.identity(L2Book, %{coin: "BTC"})
      b = SubscriptionKey.identity(L2Book, %{coin: "BTC", nSigFigs: 5})
      c = SubscriptionKey.identity(L2Book, %{"coin" => "BTC"})

      refute SubscriptionKey.same?(a, b)
      assert SubscriptionKey.same?(a, c)
    end

    test "user addresses are normalised to lower case" do
      key = SubscriptionKey.identity(UserFills, %{user: "0xAbCd"})
      assert SubscriptionKey.user(key) == "0xabcd"
    end
  end

  describe "dispatch isolation" do
    test "an l2Book subscriber for BTC never matches an ETH frame" do
      btc = SubscriptionKey.routing_key(L2Book, %{coin: "BTC"})
      eth = SubscriptionKey.routing_key(L2Book, %{coin: "ETH"})
      message = frame("l2Book", %{"coin" => "BTC", "levels" => [[], []]})

      assert SubscriptionKey.matches?(btc, message)
      refute SubscriptionKey.matches?(eth, message)
    end

    test "channels never cross-match" do
      book = SubscriptionKey.routing_key(L2Book, %{coin: "BTC"})
      trades = SubscriptionKey.routing_key(Trades, %{coin: "BTC"})

      refute SubscriptionKey.matches?(book, frame("trades", [%{"coin" => "BTC"}]))
      assert SubscriptionKey.matches?(trades, frame("trades", [%{"coin" => "BTC"}]))
    end

    test "list payloads (trades) are demultiplexed on the first element" do
      btc = SubscriptionKey.routing_key(Trades, %{coin: "BTC"})
      eth = SubscriptionKey.routing_key(Trades, %{coin: "ETH"})
      message = frame("trades", [%{"coin" => "ETH", "px" => "1"}])

      refute SubscriptionKey.matches?(btc, message)
      assert SubscriptionKey.matches?(eth, message)
    end

    test "candle matches on symbol and interval" do
      one_min = SubscriptionKey.routing_key(Candle, %{coin: "BTC", interval: "1m"})
      one_hour = SubscriptionKey.routing_key(Candle, %{coin: "BTC", interval: "1h"})
      message = frame("candle", %{"s" => "BTC", "i" => "1m", "c" => "100"})

      assert SubscriptionKey.matches?(one_min, message)
      refute SubscriptionKey.matches?(one_hour, message)
    end

    test "user channels are demultiplexed on the echoed user, case-insensitively" do
      a = SubscriptionKey.routing_key(UserFills, %{user: "0xAAA"})
      b = SubscriptionKey.routing_key(UserFills, %{user: "0xBBB"})
      message = frame("userFills", %{"user" => "0xaaa", "fills" => []})

      assert SubscriptionKey.matches?(a, message)
      refute SubscriptionKey.matches?(b, message)
    end

    test "frames without a channel match nothing (no broadcast fallback)" do
      key = SubscriptionKey.routing_key(AllMids, %{})
      refute SubscriptionKey.matches?(key, %{"data" => %{"mids" => %{}}})
      refute SubscriptionKey.matches?(key, %{})
    end

    test "a frame that echoes nothing still reaches its channel's subscribers" do
      key = SubscriptionKey.routing_key(AllMids, %{})
      assert SubscriptionKey.matches?(key, frame("allMids", %{"mids" => %{"BTC" => "1"}}))
    end
  end

  describe "group A channels" do
    test "channels with no attribution are flagged" do
      assert SubscriptionKey.group_a?(SubscriptionKey.identity(OrderUpdates, %{user: "0xa"}))
      refute SubscriptionKey.group_a?(SubscriptionKey.identity(UserFills, %{user: "0xa"}))
      assert "userEvents" in SubscriptionKey.group_a_channels()
    end

    test "an orderUpdates frame cannot be attributed, so it matches every subscriber" do
      a = SubscriptionKey.routing_key(OrderUpdates, %{user: "0xAAA"})
      message = frame("orderUpdates", [%{"order" => %{}, "status" => "open"}])

      # This is exactly why the packer allows only one group A user per socket.
      assert SubscriptionKey.matches?(a, message)
    end
  end

  describe "matches_request?/2 (raw request maps)" do
    test "matches on the request's own discriminating fields" do
      request = %{type: "l2Book", coin: "BTC"}

      assert SubscriptionKey.matches_request?(request, frame("l2Book", %{"coin" => "BTC"}))
      refute SubscriptionKey.matches_request?(request, frame("l2Book", %{"coin" => "ETH"}))
      refute SubscriptionKey.matches_request?(request, frame("trades", [%{"coin" => "BTC"}]))
    end

    test "handles string-keyed requests and webData3's nested user" do
      request = %{"type" => "webData3", "user" => "0xABC"}

      assert SubscriptionKey.matches_request?(
               request,
               frame("webData3", %{"userState" => %{"user" => "0xabc"}})
             )

      refute SubscriptionKey.matches_request?(
               request,
               frame("webData3", %{"userState" => %{"user" => "0xdef"}})
             )
    end
  end
end
