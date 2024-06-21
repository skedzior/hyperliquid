defmodule Hyperliquid.Orders do
  alias Hyperliquid.Api.{Info, Exchange, Types.OrderWire}
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
  def slippage_price(coin, is_buy, slippage \\ nil, px \\ nil) do
    slippage = slippage || @default_slippage

    px = px || get_midprice(coin)
    px = if is_buy, do: px * (1 + slippage), else: px * (1 - slippage)

    decimals = Cache.decimals_from_coin(coin)
    Float.round(px, decimals)
    |> Float.to_string()
  end

  def trigger_from_order_type(order_type) when is_binary(order_type) do
    order_type
    |> String.downcase()
    |> case do
      "gtc" -> %{limit: %{tif: "Gtc"}}
      "ioc" -> %{limit: %{tif: "Ioc"}}
      "alo" -> %{limit: %{tif: "Alo"}}
      _     -> %{limit: %{tif: order_type}}
    end
  end

  def trigger_from_order_type(order_type) when is_map(order_type) do
    %{trigger: order_type}
  end

  def market_buy(coin, sz, px \\ nil, slippage \\ @default_slippage) do
    px = slippage_price(coin, true, slippage, px)
    trigger = trigger_from_order_type("ioc")
    asset = Cache.asset_from_coin(coin)

    OrderWire.new(asset, true, px, sz, false, trigger)
    |> OrderWire.purify()
    |> Exchange.place_order()
  end

  def market_sell(coin, sz, px \\ nil, slippage \\ @default_slippage) do
    px = slippage_price(coin, false, slippage, px)
    trigger = trigger_from_order_type("ioc")
    asset = Cache.asset_from_coin(coin)

    OrderWire.new(asset, false, px, sz, false, trigger)
    |> OrderWire.purify()
    |> Exchange.place_order()
  end

  # def market_open(coin, is_buy, sz, px, order_type, slippage, cloid) do
  #   px = slippage_price(coin, is_buy, slippage, px)
  #   trigger = %{"trigger" => %{ # order_type = trigger obj
  #     isMarket: false,
  #     tpsl: "sl",
  #     triggerPx: "0.11"
  #   }}
  #   trigger = %{"limit" => %{"tif" => order_type}}
  #   Exchange.place_order(coin, is_buy, sz, px, trigger, false, cloid)
  # end

  def market_close(address, coin, sz, px, slippage \\ @default_slippage, cloid \\ nil) do
    {:ok, %{"assetPositions" => positions}} = Info.clearinghouse_state(address)

    Enum.each(positions, fn position ->
      item = position["position"]

      if coin == item["coin"] do
        szi = String.to_float(item["szi"])
        sz = if sz == nil, do: abs(szi), else: sz
        is_buy = if szi < 0, do: true, else: false
        px = slippage_price(coin, is_buy, slippage, px)
        order_type = %{"limit" => %{"tif" => "Ioc"}}
        # Market Order is an aggressive Limit Order IoC
        Exchange.place_order(coin, is_buy, sz, px, order_type, true, cloid)
      end
    end)
  end
end
