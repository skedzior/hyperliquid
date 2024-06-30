defmodule Hyperliquid.Orders do
  alias Hyperliquid.Api.{Info, Exchange}
  alias Hyperliquid.Orders.{OrderWire, PriceConverter}
  alias Hyperliquid.Cache

  @type coin :: String.t()
  @type is_buy :: boolean()
  @type slippage :: float()
  @type px :: float() | nil

  @default_slippage 0.05

  def get_midprice(coin) do
    mids = Cache.get(:all_mids)# || fetch_mids()
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

  @spec slippage_price(String.t(), boolean(), float() | nil, float() | nil) :: float()
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
    # %{
    #   "position" => %{
    #     "coin" => "SOL",
    #     "cumFunding" => %{
    #       "allTime" => "1.426902",
    #       "sinceChange" => "0.036191",
    #       "sinceOpen" => "0.036191"
    #     },
    #     "entryPx" => "137.28",
    #     "leverage" => %{"rawUsd" => "-63.414639", "type" => "isolated", "value" => 13},
    #     "liquidationPx" => "130.08131077",
    #     "marginUsed" => "7.080361",
    #     "maxLeverage" => 20,
    #     "positionValue" => "70.495",
    #     "returnOnEquity" => "0.35132576",
    #     "szi" => "0.5",
    #     "unrealizedPnl" => "1.855"
    #   },
    #   "type" => "oneWay"
    # }

    szi = String.to_float(p["szi"])
    sz = abs(szi)
    is_buy? = if szi < 0, do: true, else: false
    market_order(p["coin"], sz, is_buy?, true, vault_address, nil, slippage)
  end
end
