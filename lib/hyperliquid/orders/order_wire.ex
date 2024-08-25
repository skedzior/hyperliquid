defmodule Hyperliquid.Orders.OrderWire do
  @moduledoc """
  The OrderWire struct represents the essential parameters for placing an order on the
  Hyperliquid exchange. It encapsulates all necessary information such as asset index,
  buy/sell direction, price, size, and additional order properties.

  ## Struct Fields

    * `:a` - Asset index (integer) representing the asset's position in the coin list
    * `:b` - Boolean indicating if it's a buy order (true) or sell order (false)
    * `:p` - Limit price for the order
    * `:s` - Size of the order
    * `:r` - Boolean indicating if it's a reduce-only order
    * `:t` - Trigger conditions for the order
    * `:c` - Client Order ID (optional)

  ## Usage

  Create a new OrderWire struct:

      iex> OrderWire.new(1, true, 50000, 1.0, false, %{limit: %{tif: "Gtc"}})
      %OrderWire{a: 1, b: true, p: 50000, s: 1.0, r: false, t: %{limit: %{tif: "Gtc"}}, c: nil}

  Purify the OrderWire for API submission:

      iex> order = OrderWire.new(1, true, 50000, 1.0, false, %{limit: %{tif: "Gtc"}})
      iex> OrderWire.purify(order)
      %{a: 1, b: true, p: "50000", s: "1.0", r: false, t: %{limit: %{tif: "Gtc"}}}

  ## Full Contextual Example

  The OrderWire struct is typically used within order placement functions in the Orders module. Here's an example
  of how it is used for a `limit_order` function:

      def limit_order(asset_name, sz, is_buy?, px, tif \\ "gtc", reduce? \\ false, vault_address \\ nil) do
        trigger = trigger_from_order_type(tif)
        asset_index = Cache.asset_name_to_index(asset_name)

        OrderWire.new(asset_index, is_buy?, px, sz, reduce?, trigger)
        |> OrderWire.purify()
        |> Exchange.place_order("na", vault_address)
      end

  In this example:
  1. The function takes order details as parameters.
  2. It determines the trigger type and fetches the asset index for the given coin.
  3. An OrderWire struct is created using the `new/7` function.
  4. The struct is then purified using the `purify/1` function.
  5. Finally, the purified order data is passed to an `Exchange.place_order/3` function for execution.

  This demonstrates how OrderWire fits into the broader order placement process, encapsulating
  order details in a standardized format before submission to the exchange.

  Note: The `purify/1` function converts numeric values to strings and removes nil fields,
  preparing the order data for API submission. The asset index (`:a`) remains an integer.

  Important: Ensure you're using the correct asset index based on the current coin list.
  """

  import Hyperliquid.Utils

  defstruct [:a, :b, :p, :s, :r, :t, c: nil]

  @doc """
  Creates a new OrderWire struct.
  """
  def new(asset, is_buy, limit_px, sz, reduce_only, trigger, cloid \\ nil) do
    %__MODULE__{
      a: asset,
      b: is_buy,
      p: limit_px,
      s: sz,
      r: reduce_only,
      t: trigger,
      c: cloid
    }
  end

  @doc """
  Converts price and size to string if they are integer or float, and removes nil values from the struct.
  """
  def purify(%__MODULE__{} = wire) do
    wire
    |> numbers_to_strings([:p, :s])
    |> Map.from_struct()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end
end
