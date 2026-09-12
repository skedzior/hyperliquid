defmodule Hyperliquid.Utils.NumberFormatTest do
  @moduledoc """
  H1: prices/sizes below `1e-4` used to be serialized as `"1.0e-5"` and shipped
  *inside the signed action*, so the rejection surfaced as an opaque signature
  error. `Hyperliquid.Utils.float_to_wire/1` mirrors the Python SDK's
  `float_to_wire/1` (`f"{x:.8f}"` -> `Decimal(...).normalize()`), including its
  rounding guard.
  """

  use ExUnit.Case, async: true

  alias Hyperliquid.Utils
  alias Hyperliquid.Utils.Format

  doctest Hyperliquid.Utils, only: [float_to_wire: 1]

  describe "float_to_wire/1 never emits exponent notation" do
    test "sub-1e-4 floats" do
      assert Utils.float_to_wire(0.00001) == "0.00001"
      assert Utils.float_to_wire(0.0000123) == "0.0000123"
      assert Utils.float_to_wire(0.00000001) == "0.00000001"
      assert Utils.float_to_wire(-0.00001) == "-0.00001"
    end

    test "no value in 1e-8..1e8 round-trips through scientific notation" do
      for exp <- -8..8, mantissa <- [1, 3, 7] do
        value = mantissa * :math.pow(10, exp)
        wire = Utils.float_to_wire(Float.round(value, 8))

        refute String.contains?(wire, "e"),
               "#{inspect(value)} formatted as #{wire}"

        assert Regex.match?(~r/^-?\d+(\.\d+)?$/, wire)
      end
    end
  end

  describe "float_to_wire/1 matches the Python SDK" do
    test "integers carry no trailing .0" do
      assert Utils.float_to_wire(27) == "27"
      assert Utils.float_to_wire(27.0) == "27"
      assert Utils.float_to_wire(0) == "0"
      assert Utils.float_to_wire(0.0) == "0"
      assert Utils.float_to_wire(-0.0) == "0"
    end

    test "float noise is absorbed by the 8-decimal rendering" do
      assert Utils.float_to_wire(0.1 + 0.2) == "0.3"
      assert Utils.float_to_wire(1.033) == "1.033"
      assert Utils.float_to_wire(0.00001231) == "0.00001231"
    end

    test "very large values stay in fixed notation" do
      assert Utils.float_to_wire(100_000_000.0) == "100000000"
      assert Utils.float_to_wire(123_456_789.0) == "123456789"
      assert Utils.float_to_wire(1.0e20) == "100000000000000000000"
      assert Utils.float_to_wire(123_123_123_123) == "123123123123"
    end

    test "a value that does not fit in 8 decimals raises rather than truncating" do
      # Same input the Python SDK's `test_float_to_int_for_hashing` rejects.
      assert_raise ArgumentError, ~r/causes rounding/, fn ->
        Utils.float_to_wire(0.000012312312)
      end

      assert {:error, _} = Utils.safe_float_to_wire(0.000012312312)
    end
  end

  describe "float_to_wire/1 on binaries" do
    test "already-formatted strings are not re-parsed through a float" do
      assert Utils.float_to_wire("0.00001") == "0.00001"
      assert Utils.float_to_wire("1000.456789") == "1000.456789"
      # 20 significant digits: a Float.parse/1 round-trip would destroy these.
      assert Utils.float_to_wire("1.00000000000000000001") == "1.00000000000000000001"
    end

    test "redundant zeros are trimmed textually" do
      assert Utils.float_to_wire("100.0") == "100"
      assert Utils.float_to_wire("50.500") == "50.5"
      assert Utils.float_to_wire("-0.0") == "0"
    end

    test "exponent notation supplied as a string is expanded" do
      assert Utils.float_to_wire("1.0e-5") == "0.00001"
      assert Utils.float_to_wire("1.23E-7") == "0.000000123"
      assert Utils.float_to_wire("1e3") == "1000"
      assert Utils.float_to_wire("-2.5e-3") == "-0.0025"
    end

    test "non-numeric strings pass through untouched" do
      assert Utils.float_to_wire("na") == "na"
    end
  end

  describe "Format.format_price/3 and format_size/2 with small floats" do
    test "float prices below 1e-4 are formatted, not exponentiated" do
      assert Format.format_price(0.00001, 0, perp: false) == "0.00001"
      assert Format.format_price(0.0000123456789, 0, perp: false) == "0.00001234"
      refute String.contains?(Format.format_price(1.0e-5, 2), "e")
    end

    test "float sizes below 1e-4 are formatted, not exponentiated" do
      assert Format.format_size(0.00001, 5) == "0.00001"
      assert Format.format_size(1.0e-5, 8) == "0.00001"
      refute String.contains?(Format.format_size(1.0e-5, 8), "e")
    end

    test "integers and large values still work" do
      assert Format.format_price(50_000, 5) == "50000"
      assert Format.format_price(27.0, 2) == "27"
      assert Format.format_size(0.001, 3) == "0.001"
    end
  end

  describe "generate_nonce/0 (M14)" do
    test "is strictly increasing under concurrency" do
      nonces =
        1..500
        |> Task.async_stream(fn _ -> Utils.generate_nonce() end, max_concurrency: 50)
        |> Enum.map(fn {:ok, n} -> n end)

      assert length(Enum.uniq(nonces)) == length(nonces)
    end

    test "is monotonic within a single process" do
      seq = for _ <- 1..100, do: Utils.generate_nonce()
      assert seq == Enum.sort(seq)
      assert Enum.uniq(seq) == seq
    end
  end
end
