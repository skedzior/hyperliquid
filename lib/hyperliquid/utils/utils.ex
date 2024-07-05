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

  @pubsub Hyperliquid.PubSub

  def subscribe(channel) do
    Phoenix.PubSub.subscribe(@pubsub, channel)
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

  @doc """
  Utils for converting map keys to atoms.
  """
  def atomize_keys(data) when is_map(data) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      atom_key = if is_binary(key), do: String.to_atom(key), else: key
      Map.put(acc, atom_key, atomize_keys(value))
    end)
  end

  def atomize_keys(data) when is_list(data) do
    Enum.map(data, &atomize_keys/1)
  end

  def atomize_keys({key, value}) when is_binary(key) do
    atom_key = String.to_atom(key)
    {atom_key, atomize_keys(value)}
  end

  def atomize_keys({key, value}) do
    {key, atomize_keys(value)}
  end

  def atomize_keys(data), do: data
end
