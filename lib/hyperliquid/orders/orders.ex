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

    # Retrieve mid-price for a coin
    mid_price = Hyperliquid.Orders.get_midprice("BTC")

    # Place a market buy order
    Hyperliquid.Orders.market_buy("ETH", 1.0, "0x123...")

    # Place a limit sell order
    Hyperliquid.Orders.limit_order("BTC", 0.5, false, 50000, "gtc", false, "0x123...")

    # Close all positions for an address
    Hyperliquid.Orders.market_close("0x123...")
  """

  alias Hyperliquid.Api.{Info, Exchange}
  alias Hyperliquid.Orders.{OrderWire, PriceConverter}
  alias Hyperliquid.Cache

  @default_slippage 0.05

  def get_midprice(coin) do
    mids = Cache.get(:all_mids) || fetch_mids()
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

  def slippage_price(coin, is_buy?, slippage \\ @default_slippage, px \\ nil) do
    px = px || get_midprice(coin)
    px = if is_buy?, do: px * (1 + slippage), else: px * (1 - slippage)

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

  def market_buy(coin, sz, vault_address \\ nil), do:
    market_order(coin, sz, true, false, vault_address, nil, @default_slippage)

  def market_sell(coin, sz, vault_address \\ nil), do:
    market_order(coin, sz, false, false, vault_address, nil, @default_slippage)

  def market_order(coin, sz, is_buy?, reduce?, vault_address \\ nil, px \\ nil, slippage \\ @default_slippage) do
    px = slippage_price(coin, is_buy?, slippage, px)
    trigger = trigger_from_order_type("ioc")
    asset = Cache.asset_from_coin(coin)

    OrderWire.new(asset, is_buy?, px, sz, reduce?, trigger)
    |> OrderWire.purify()
    |> Exchange.place_order("na", vault_address)
  end

  def limit_order(coin, sz, is_buy?, px, tif \\ "gtc", reduce? \\ false, vault_address \\ nil) do
    trigger = trigger_from_order_type(tif)
    asset = Cache.asset_from_coin(coin)

    OrderWire.new(asset, is_buy?, px, sz, reduce?, trigger)
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
    is_buy? = if szi < 0, do: true, else: false
    market_order(p["coin"], sz, is_buy?, true, vault_address, nil, slippage)
  end
end
