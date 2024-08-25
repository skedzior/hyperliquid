defmodule Hyperliquid.Orders do
  @moduledoc """
  Provides helper methods for order creation and management.

  This module offers a set of functions to facilitate various order operations, including:
  - Retrieving and calculating mid-prices
  - Creating market and limit orders
  - Handling order types and triggers
  - Managing position closures

  Key features:
  - Mid-price retrieval with caching mechanism
  - Slippage price calculation for market orders
  - Support for various order types (GTC, IOC, ALO)
  - Market buy and sell order creation
  - Limit order creation with customizable time-in-force
  - Position closing functionality

  The module interacts with the Hyperliquid API and cache to ensure efficient
  and accurate order processing. It handles both perpetual and spot markets,
  and provides flexibility in order parameters such as size, price, and slippage.

  Usage examples:

    # Retrieve mid-price for an asset
      mid_price = Hyperliquid.Orders.get_midprice("SOL")
      135.545

      mid_price = Hyperliquid.Orders.get_midprice("PURR/USDC")
      0.18546

    # Place a market buy order
    Hyperliquid.Orders.market_buy("ETH", 1.0, "0x123...")
    {:ok,
      %{
        "response" => %{
          "data" => %{
            "statuses" => [
              %{"filled" => %{"avgPx" => "128.03", "oid" => 17114311614, "totalSz" => "1.0"}}
            ]
          },
          "type" => "order"
        },
        "status" => "ok"
      }}

    # Place a limit sell order
    Hyperliquid.Orders.limit_order("BTC", 0.5, false, 50000, "gtc", false, "0x123...")
    {:ok,
      %{
        "response" => %{
          "data" => %{"statuses" => [%{"resting" => %{"oid" => 10030901240}}]},
          "type" => "order"
        },
        "status" => "ok"
      }}

    # Close list of positions
    {:ok, %{"assetPositions" => positions}} = Info.clearinghouse_state("0x123")
    Hyperliquid.Orders.market_close(positions)

    # Close single position
    positions
    |> Enum.at(0)
    |> Hyperliquid.Orders.market_close()

    # Close all positions for an address
    Hyperliquid.Orders.market_close("0x123...")
    [
      ok: %{
        "response" => %{
          "data" => %{
            "statuses" => [
              %{"filled" => %{"avgPx" => "148.07", "oid" => 10934427319, "totalSz" => "1.0"}}
            ]
          },
          "type" => "order"
        },
        "status" => "ok"
      }
    ]
  """

  alias Hyperliquid.Api.{Info, Exchange}
  alias Hyperliquid.Orders.{OrderWire, PriceConverter}
  alias Hyperliquid.Cache

  @default_slippage 0.05

  def get_midprice(asset_name) do
    coin = Cache.asset_name_to_coin(asset_name)
    mids = Cache.all_mids() || fetch_mids()
    coin = String.to_existing_atom(coin)

    case Map.get(mids, coin) do
      nil -> raise "Midprice for #{coin} not found"
      price -> String.to_float(price)
    end
  end

  defp fetch_mids do
    case Info.all_mids() do
      {:ok, mids} -> mids
      _ -> raise "Unable to fetch mids from api"
    end
  end

  def slippage_price(asset_name, buy?, slippage \\ @default_slippage, px \\ nil) do
    px = px || get_midprice(asset_name)
    px = if buy?, do: px * (1 + slippage), else: px * (1 - slippage)

    case PriceConverter.convert_price(px, :perp) do
      {:ok, px} -> px
      _ -> px
    end
  end

  def trigger_from_order_type(type) when is_binary(type) do
    type
    |> String.downcase()
    |> case do
      "gtc" -> %{limit: %{tif: "Gtc"}}
      "ioc" -> %{limit: %{tif: "Ioc"}}
      "alo" -> %{limit: %{tif: "Alo"}}
      _     -> %{limit: %{tif: type}}
    end
  end

  def trigger_from_order_type(type) when is_map(type), do: %{trigger: type}

  def market_buy(asset_name, sz, vault_address \\ nil), do:
    market_order(asset_name, sz, true, false, vault_address, nil, @default_slippage)

  def market_sell(asset_name, sz, vault_address \\ nil), do:
    market_order(asset_name, sz, false, false, vault_address, nil, @default_slippage)

  def market_order(asset_name, sz, buy?, reduce?, vault_address \\ nil, px \\ nil, slippage \\ @default_slippage) do
    px = slippage_price(asset_name, buy?, slippage, px)
    trigger = trigger_from_order_type("ioc")
    asset_index = Cache.asset_name_to_index(asset_name)

    OrderWire.new(asset_index, buy?, px, sz, reduce?, trigger)
    |> OrderWire.purify()
    |> Exchange.place_order("na", vault_address)
  end

  def limit_order(asset_name, sz, buy?, px, tif \\ "gtc", reduce? \\ false, vault_address \\ nil) do
    trigger = trigger_from_order_type(tif)
    asset_index = Cache.asset_name_to_index(asset_name)

    OrderWire.new(asset_index, buy?, px, sz, reduce?, trigger)
    |> OrderWire.purify()
    |> Exchange.place_order("na", vault_address)
  end

  def market_close(position, slippage \\ @default_slippage, vault_address \\ nil)
  def market_close(address, slippage, vault_address) when is_binary(address) do
    {:ok, %{"assetPositions" => positions}} = Info.clearinghouse_state(address)

    market_close(positions, slippage, vault_address)
  end

  def market_close(positions, slippage, vault_address) when is_list(positions) do
    Enum.map(positions, &market_close(&1, slippage, vault_address))
  end

  def market_close(%{"position" => p}, slippage, vault_address) do
    szi = String.to_float(p["szi"])
    sz = abs(szi)
    buy? = if szi < 0, do: true, else: false
    market_order(p["coin"], sz, buy?, true, vault_address, nil, slippage)
  end
end
