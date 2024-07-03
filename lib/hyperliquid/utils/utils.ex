defmodule Hyperliquid.Utils do
  @moduledoc """
  Provides utility functions for the Hyperliquid application.

  This module offers a collection of helper functions that are used across the
  Hyperliquid application. It includes utilities for data manipulation,
  PubSub operations, number formatting, random ID generation, and hexadecimal
  conversions.

  ## Key Features

  - Atomize keys in data structures
  - PubSub subscription and broadcasting
  - Number to string conversions with special float handling
  - Random client order ID (cloid) generation
  - Hexadecimal string manipulations
  - Timestamp generation
  """
  alias Hyperliquid.Atomizer

  def atomize_keys(data), do: Atomizer.atomize_keys(data)

  @pubsub Hyperliquid.PubSub

  def subscribe(channel) do
    Phoenix.PubSub.subscribe(@pubsub, channel)
  end

  def broadcast(channel, payload) do
    Phoenix.PubSub.broadcast(@pubsub, channel, payload)
  end

  def numbers_to_strings(struct, fields) do
    Enum.reduce(fields, struct, fn field, acc ->
      value = Map.get(acc, field)
      Map.put(acc, field, float_to_string(value))
    end)
  end

  def float_to_string(value) when is_float(value) do
    if value == trunc(value) do
      Integer.to_string(trunc(value))
    else
      Float.to_string(value)
    end
  end

  def float_to_string(value) when is_integer(value) do
    Integer.to_string(value)
  end

  def float_to_string(value) when is_binary(value) do
    case Float.parse(value) do
      {float_value, ""} -> float_to_string(float_value)
      :error -> value
    end
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
