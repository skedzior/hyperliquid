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
    wire
    |> numbers_to_strings([:p, :s])
    # |> PriceConverter.convert_price(wire.p, type)
    |> Map.from_struct()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end
end
  # def order_request_to_order_wire(order, asset) do
  #   order_wire = %{
  #     "a" => asset,
  #     "b" => order["is_buy"],
  #     "p" => float_to_int_for_hashing(order["limit_px"]),
  #     "s" => float_to_int_for_hashing(order["sz"]),
  #     "r" => order["reduce_only"],
  #     "t" => order_type_to_wire(order["order_type"])
  #   }
  #   # if "cloid" in order and order["cloid"] is not None:
  #   #     order_wire["c"] = order["cloid"].to_raw()
  #   order_wire
  # end

  # def order_wires_to_order_action(order_wires) do
  #  %{
  #     "type" => "order",
  #     "orders" => order_wires,
  #     "grouping" => "na",
  #   }
  # end
