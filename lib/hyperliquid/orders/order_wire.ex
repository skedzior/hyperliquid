defmodule Hyperliquid.Orders.OrderWire do
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
  def purify(%__MODULE__{} = wire, type \\ :perp) do
    #TODO: implement PriceConverter.convert_price(wire.p, type)
    wire
    |> numbers_to_strings([:p, :s])
    |> Map.from_struct()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end
end
