defmodule Hyperliquid.Orders.PriceConverter do
  def convert_price(price, type \\ :perp)
  def convert_price(price, type) when type in [:perp, :spot] do
    cond do
      is_binary(price) ->
        case Float.parse(price) do
          {float_value, ""} -> convert_significant_figures_and_decimals(float_value, type)
          :error -> {:error, "Invalid number format"}
        end

      is_float(price) ->
        convert_significant_figures_and_decimals(price, type)

      is_integer(price) ->
        convert_significant_figures_and_decimals(price, type)

      true ->
        {:error, "Unsupported price format"}
    end
  end

  defp convert_significant_figures_and_decimals(value, :perp) do
    rounded_value = round_to_significant_figures(value, 5)
    rounded_value = round_to_decimal_places(rounded_value, 6)

    if valid_decimal_places?(rounded_value, 6) do
      {:ok, Float.to_string(rounded_value)}
    else
      {:error, "Unable to convert to valid perp price"}
    end
  end

  defp convert_significant_figures_and_decimals(value, :spot) do
    rounded_value = round_to_significant_figures(value, 5)
    rounded_value = round_to_decimal_places(rounded_value, 8)

    if valid_decimal_places?(rounded_value, 8) do
      {:ok, Float.to_string(rounded_value)}
    else
      {:error, "Unable to convert to valid spot price"}
    end
  end

  defp round_to_significant_figures(0, _sig_figs), do: 0

  defp round_to_significant_figures(value, sig_figs) do
    power = :math.pow(10, sig_figs - :math.ceil(:math.log10(abs(value))))
    round(value * power) / power
  end

  defp round_to_decimal_places(value, decimal_places) do
    factor = :math.pow(10, decimal_places)
    Float.round(value * factor) / factor
  end

  defp valid_decimal_places?(value, max_decimal_places) do
    decimal_places =
      value
      |> Float.to_string()
      |> String.split(".")
      |> case do
           [_whole] -> 0
           [_whole, fraction] -> String.length(fraction)
         end

    decimal_places <= max_decimal_places
  end
end
