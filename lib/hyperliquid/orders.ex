defmodule Hyperliquid.Orders do
  alias Hyperliquid.Api.Info

  @type coin :: String.t()
  @type is_buy :: boolean()
  @type slippage :: float()
  @type px :: float() | nil

  @default_slippage 0.05

  #TODO: move to ets - replace with lookup
  def get_midprice(coin) do
    {:ok, mids} = Info.all_mids()

    mids[coin] |> String.to_float()
  end

  @spec slippage_price(coin, is_buy, slippage, px) :: float()
  def slippage_price(coin, is_buy, slippage, px \\ nil) do
    # TODO: post to ws or get directly from state
    px = px || get_midprice(coin)
      # case px do
      #   nil -> get_midprice(coin)
      #   _ -> px
      # end

    px = if is_buy, do: px * (1 + slippage), else: px * (1 - slippage)

    decimals = Cache.get(:decimal_map)[coin]

    Float.round(px, decimals)
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

  def market_open(coin, is_buy, sz, px, slippage, order_type, cloid \\ nil) do
    px = slippage_price(coin, is_buy, slippage, px)
    trigger = trigger_from_order_type(order_type)
    Exchange.place_order(coin, is_buy, sz, px, trigger, false, cloid)
  end

  def market_open(coin, is_buy, sz, px, slippage, order_type, cloid) do
    px = slippage_price(coin, is_buy, slippage, px)
    trigger = %{"trigger" => %{ # order_type = trigger obj
      isMarket: false,
      tpsl: "sl",
      triggerPx: "0.11"
    }}
    trigger = %{"limit" => %{"tif" => order_type}}
    Exchange.place_order(coin, is_buy, sz, px, trigger, false, cloid)
  end

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
