defmodule Hyperliquid.Utils do
  alias Hyperliquid.Api.Info

  @pubsub Hyperliquid.PubSub

  def subscribe(channel) do
    Phoenix.PubSub.subscribe(@pubsub, channel)
  end

  def broadcast(channel, payload) do
    Phoenix.PubSub.broadcast(@pubsub, channel, payload)
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

  def asset_map do
    Info.meta()
    |> elem(1)
    |> Map.get("universe")
    |> Enum.with_index(&{&1["name"], &2})
    |> Enum.into(%{})
  end

  def atomize_map(map) do
    map
    |> Jason.encode!()
    |> Jason.decode!(keys: :atoms)
  end

  def make_cloid do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  def hex_string_to_integer(hex_string) do
    hex_string
    |> String.trim_leading("0x")
    |> Base.decode16!(case: :lower)
    |> :binary.decode_unsigned()
  end

  def to_hex(number) when is_nil(number), do: nil

  def to_hex(number) when is_number(number) do
    Integer.to_string(number, 16)
    |> String.downcase()
    |> then(&"0x#{&1}")
  end

  def to_full_hex(number) when is_number(number) do
    Integer.to_string(number, 16)
    |> String.downcase()
    |> then(&"0x#{String.duplicate("0", 40 - String.length(&1))}#{&1}")
  end

  def trim_0x(nil), do: nil
  def trim_0x(string), do: Regex.replace(~r/^0x/, string, "")

  def get_timestamp, do: :os.system_time(:millisecond)
end
