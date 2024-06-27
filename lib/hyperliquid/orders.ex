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
  def slippage_price(coin, is_buy?, slippage \\ @default_slippage, px \\ nil) do
    px = px || get_midprice(coin)
    px = if is_buy?, do: px * (1 + slippage), else: px * (1 - slippage)

    decimals = Cache.decimals_from_coin(coin)
    Float.round(px, decimals)
    |> Float.to_string()
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
    market_order(coin, sz, true, vault_address, nil, @default_slippage)

  def market_sell(coin, sz, vault_address \\ nil), do:
    market_order(coin, sz, false, vault_address, nil, @default_slippage)

  def market_order(coin, sz, is_buy?, vault_address \\ nil, px \\ nil, slippage \\ @default_slippage) do
    px = slippage_price(coin, is_buy?, slippage, px)
    trigger = trigger_from_order_type("ioc")
    asset = Cache.asset_from_coin(coin)

    OrderWire.new(asset, is_buy?, px, sz, false, trigger)
    |> IO.inspect()
    |> OrderWire.purify()
    |> Exchange.place_order("na", vault_address)
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
