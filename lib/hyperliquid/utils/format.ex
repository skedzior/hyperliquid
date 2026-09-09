defmodule Hyperliquid.Utils.Format do
  @moduledoc """
  Formatting utilities for Hyperliquid prices and sizes.

  Implements Hyperliquid's tick and lot size rules:
  - Prices: Maximum 5 significant figures, max 6 (perp) or 8 (spot) - szDecimals decimals
  - Sizes: Truncated to szDecimals decimal places

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/tick-and-lot-size
  """

  @doc """
  Format price according to Hyperliquid rules.

  Rules:
  - Maximum 5 significant figures
  - Maximum 6 (for perp) or 8 (for spot) - szDecimals decimal places
  - Integer prices are always allowed regardless of significant figures

  ## Parameters
    - `price`: Price as string, integer, or float
    - `sz_decimals`: Size decimals for the asset
    - `opts`: Options
      - `:perp` - true for perpetual (default), false for spot

  ## Examples

      iex> Format.format_price("50000.123456", 5)
      "50000"

      iex> Format.format_price("0.0000123456789", 0, perp: false)
      "0.00001234"

      iex> Format.format_price(50000, 5)
      "50000"
  """
  def format_price(price, sz_decimals, opts \\ []) do
    is_perp = Keyword.get(opts, :perp, true)
    price_str = Hyperliquid.Utils.to_plain_string(price) |> String.trim()

    # Integer prices are always allowed
    if Regex.match?(~r/^-?\d+$/, price_str) do
      trim_zeros(price_str)
    else
      # Apply decimal limit: max 6 (perp) or 8 (spot) - szDecimals
      max_decimals = max(if(is_perp, do: 6, else: 8) - sz_decimals, 0)
      price_str = to_fixed_truncate(price_str, max_decimals)

      # Apply sig figs limit: max 5 significant figures
      price_str = to_precision_truncate(price_str, 5)

      price_str
    end
  end

  @doc """
  Format size according to Hyperliquid rules.

  Rules:
  - Truncate decimal places to szDecimals

  ## Parameters
    - `size`: Size as string, integer, or float
    - `sz_decimals`: Size decimals for the asset

  ## Examples

      iex> Format.format_size("1.23456789", 5)
      "1.23456"

      iex> Format.format_size(0.001, 3)
      "0.001"
  """
  def format_size(size, sz_decimals) do
    size_str = Hyperliquid.Utils.to_plain_string(size) |> String.trim()
    to_fixed_truncate(size_str, sz_decimals)
  end

  @doc """
  Get the maximum allowed price decimals for an asset.

  ## Parameters
    - `asset_id`: Asset index
    - `sz_decimals`: Size decimals for the asset

  ## Returns
    Maximum decimal places allowed for price
  """
  def max_price_decimals(asset_id, sz_decimals) do
    # Spot assets are 10000-99999
    max_decimals = if asset_id >= 10_000 and asset_id < 100_000, do: 8, else: 6
    max(max_decimals - sz_decimals, 0)
  end

  # ===================== String Math Operations =====================

  @doc """
  Truncate to a certain number of decimal places.

  ## Examples

      iex> Format.to_fixed_truncate("1.23456789", 5)
      "1.23456"

      iex> Format.to_fixed_truncate("100.999", 2)
      "100.99"
  """
  def to_fixed_truncate(value, decimals) when decimals >= 0 do
    case String.split(value, ".") do
      [int] ->
        trim_zeros(int)

      [int, _dec] when decimals == 0 ->
        trim_zeros(int)

      [int, dec] ->
        truncated_dec = String.slice(dec, 0, decimals)
        trim_zeros("#{int}.#{truncated_dec}")
    end
  end

  @doc """
  Truncate to a certain number of significant figures.

  ## Examples

      iex> Format.to_precision_truncate("123456", 5)
      "123450"

      iex> Format.to_precision_truncate("0.00012345", 3)
      "0.000123"
  """
  def to_precision_truncate(value, precision) when precision >= 1 do
    # Handle zero specially
    if Regex.match?(~r/^-?0+(\.0*)?$/, value) do
      "0"
    else
      {negative, abs_value} =
        if String.starts_with?(value, "-") do
          {true, String.slice(value, 1..-1//1)}
        else
          {false, value}
        end

      # Get magnitude (position of most significant digit)
      magnitude = log10_floor(abs_value)

      # Calculate shift amount
      shift_amount = precision - magnitude - 1

      # Shift right, truncate, shift back
      shifted = multiply_by_pow10(abs_value, shift_amount)
      truncated = trunc_string(shifted)
      result = multiply_by_pow10(truncated, -shift_amount)

      result = if negative, do: "-#{result}", else: result
      trim_zeros(result)
    end
  end

  # Floor log10 - position of most significant digit
  defp log10_floor(value) do
    case String.split(value, ".") do
      [int] ->
        # Integer: magnitude = length - 1
        trimmed = String.replace_leading(int, "0", "")

        if trimmed == "" do
          -1
        else
          String.length(trimmed) - 1
        end

      [int, dec] ->
        int_val = String.to_integer(int)

        if int_val != 0 do
          # Number >= 1
          trimmed = String.replace_leading(int, "0", "")
          String.length(trimmed) - 1
        else
          # Number < 1: count leading zeros in decimal
          leading_zeros =
            dec
            |> String.graphemes()
            |> Enum.take_while(&(&1 == "0"))
            |> length()

          -(leading_zeros + 1)
        end
    end
  end

  # Multiply by 10^exp (shift decimal point)
  defp multiply_by_pow10(value, 0), do: trim_zeros(value)

  defp multiply_by_pow10(value, exp) when is_integer(exp) do
    {negative, abs_value} =
      if String.starts_with?(value, "-") do
        {true, String.slice(value, 1..-1//1)}
      else
        {false, value}
      end

    {int, dec} =
      case String.split(abs_value, ".") do
        [i] -> {i, ""}
        [i, d] -> {i, d}
      end

    # Normalize empty integer
    int = if int == "", do: "0", else: int

    result =
      if exp > 0 do
        # Shift right
        if exp >= String.length(dec) do
          int <> dec <> String.duplicate("0", exp - String.length(dec))
        else
          int <> String.slice(dec, 0, exp) <> "." <> String.slice(dec, exp..-1//1)
        end
      else
        # Shift left
        abs_exp = -exp

        if abs_exp >= String.length(int) do
          "0." <> String.duplicate("0", abs_exp - String.length(int)) <> int <> dec
        else
          String.slice(int, 0, String.length(int) - abs_exp) <>
            "." <> String.slice(int, -abs_exp..-1//1) <> dec
        end
      end

    result = if negative, do: "-#{result}", else: result
    trim_zeros(result)
  end

  # Get integer part of string number
  defp trunc_string(value) do
    case String.split(value, ".") do
      [int] -> int
      [int, _dec] -> if int == "", do: "0", else: int
    end
  end

  # Trim leading and trailing zeros
  defp trim_zeros(value) do
    value
    # Remove leading zeros (but keep one before decimal)
    |> String.replace(~r/^(-?)0+(?=\d)/, "\\1")
    # Remove trailing zeros after decimal
    |> String.replace(~r/\.0*$|(\.\d+?)0+$/, "\\1")
    # Add leading zero if starts with decimal
    |> String.replace(~r/^(-?)\./, "\\g{1}0.")
    # Handle empty string
    |> then(fn s -> if s == "" or s == "-", do: "0", else: s end)
    # Normalize negative zero
    |> String.replace(~r/^-0$/, "0")
  end
end
