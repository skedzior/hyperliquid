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

  @doc """
  Convert a hex string (0x-prefixed) to an integer.
  Pass-through for integers and nil.
  """
  @spec to_int(String.t() | integer() | nil) :: integer() | nil
  def to_int("0x" <> hex) do
    {int, ""} = Integer.parse(hex, 16)
    int
  end

  def to_int(int) when is_integer(int), do: int
  def to_int(nil), do: nil

  @doc """
  Convert a non-negative integer to a 0x-prefixed lowercase hex string.
  """
  @spec from_int(non_neg_integer()) :: String.t()
  def from_int(int) when is_integer(int) and int >= 0 do
    "0x" <> String.downcase(Integer.to_string(int, 16))
  end

  def numbers_to_strings(struct, fields) do
    Enum.reduce(fields, struct, fn field, acc ->
      value = Map.get(acc, field)
      Map.put(acc, field, float_to_string(value))
    end)
  end

  # Number of decimals Hyperliquid accepts on the wire for prices/sizes.
  @wire_decimals 8
  # Same tolerance the Python SDK uses in `float_to_wire/1`.
  @wire_rounding_tolerance 1.0e-12

  @doc """
  Format a number for the Hyperliquid wire, matching the Python SDK's
  `hyperliquid.utils.signing.float_to_wire/1` semantics exactly.

  Rules:

    * fixed-point notation only — never scientific notation (`1.0e-5` is a
      signature-breaking wire value),
    * the float is rendered with 8 decimals and then normalized: trailing
      zeros and a trailing `.` are removed, `-0` becomes `0`,
    * a value that cannot be represented in 8 decimals (loss `>= 1.0e-12`)
      raises, rather than being silently truncated inside a signed action,
    * integers are rendered without a `.0` suffix,
    * binaries are **not** re-parsed through `Float.parse/1` (which is what
      re-introduced exponent notation for already-formatted values). A string
      that is already a plain decimal numeral only has its redundant zeros
      trimmed textually, so digits beyond float precision survive; exponent
      notation is expanded textually as well.

  ## Examples

      iex> Hyperliquid.Utils.float_to_wire(0.00001)
      "0.00001"

      iex> Hyperliquid.Utils.float_to_wire(0.1 + 0.2)
      "0.3"

      iex> Hyperliquid.Utils.float_to_wire(27)
      "27"

      iex> Hyperliquid.Utils.float_to_wire(27.0)
      "27"

      iex> Hyperliquid.Utils.float_to_wire("0.00001")
      "0.00001"
  """
  @spec float_to_wire(number() | String.t()) :: String.t()
  def float_to_wire(value) when is_float(value) do
    rounded = :erlang.float_to_binary(value, decimals: @wire_decimals)

    if abs(String.to_float(rounded) - value) >= @wire_rounding_tolerance do
      raise ArgumentError,
            "float_to_wire causes rounding: #{inspect(value)} does not fit in " <>
              "#{@wire_decimals} decimals"
    end

    normalize_decimal_string(rounded)
  end

  def float_to_wire(value) when is_integer(value), do: Integer.to_string(value)

  def float_to_wire(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      Regex.match?(~r/^-?\d+(\.\d+)?$/, trimmed) -> normalize_decimal_string(trimmed)
      Regex.match?(~r/^-?(\d+\.?\d*|\.\d+)[eE][-+]?\d+$/, trimmed) -> expand_exponent(trimmed)
      true -> value
    end
  end

  @doc """
  Render a number in plain (never scientific) decimal notation, preserving all
  significant digits and applying no rounding check.

  This is the input normalizer for `Hyperliquid.Utils.Format`, which does its
  own tick/lot truncation. Use `float_to_wire/1` for values that go straight
  onto the wire.
  """
  @spec to_plain_string(number() | String.t()) :: String.t()
  def to_plain_string(value) when is_float(value) do
    value
    |> :erlang.float_to_binary([:short])
    |> float_to_wire()
  end

  def to_plain_string(value) when is_integer(value), do: Integer.to_string(value)
  def to_plain_string(value) when is_binary(value), do: float_to_wire(value)
  def to_plain_string(value), do: to_string(value)

  @doc """
  Non-raising variant of `float_to_wire/1`.
  """
  @spec safe_float_to_wire(number() | String.t()) :: {:ok, String.t()} | {:error, term()}
  def safe_float_to_wire(value) do
    {:ok, float_to_wire(value)}
  rescue
    e in ArgumentError -> {:error, e.message}
  end

  @doc """
  Deprecated alias for `float_to_wire/1`, kept for backwards compatibility.
  """
  @spec float_to_string(number() | String.t()) :: String.t()
  def float_to_string(value), do: float_to_wire(value)

  # Rewrites scientific notation into plain decimal notation without going
  # through `Float.parse/1` (which would re-introduce the exponent form).
  defp expand_exponent(string) do
    [mantissa, exponent] = String.split(string, ~r/[eE]/, parts: 2)
    exponent = String.to_integer(exponent)

    {sign, mantissa} =
      case mantissa do
        "-" <> rest -> {"-", rest}
        "+" <> rest -> {"", rest}
        rest -> {"", rest}
      end

    {int, dec} =
      case String.split(mantissa, ".", parts: 2) do
        [i] -> {i, ""}
        [i, d] -> {i, d}
      end

    digits = int <> dec
    point = String.length(int) + exponent

    {int_part, dec_part} =
      cond do
        point <= 0 ->
          {"0", String.duplicate("0", -point) <> digits}

        point >= String.length(digits) ->
          {digits <> String.duplicate("0", point - String.length(digits)), ""}

        true ->
          {String.slice(digits, 0, point), String.slice(digits, point..-1//1)}
      end

    normalize_decimal_string(
      sign <> int_part <> if(dec_part == "", do: "", else: "." <> dec_part)
    )
  end

  defp normalize_decimal_string(string) do
    string
    |> then(fn s ->
      if String.contains?(s, ".") do
        s |> String.replace(~r/0+$/, "") |> String.replace(~r/\.$/, "")
      else
        s
      end
    end)
    |> String.replace(~r/^(-?)0+(?=\d)/, "\\1")
    |> then(fn
      "" -> "0"
      "-" -> "0"
      "-0" -> "0"
      s -> s
    end)
  end

  @doc """
  Monotonically increasing millisecond nonce, shared process-wide.

  Hyperliquid requires nonces to be strictly increasing per address. Plain
  `System.system_time(:millisecond)` collides when two calls land in the same
  millisecond and regresses when the wall clock steps backwards, so the value
  is clamped to `max(now, last + 1)` through an `:atomics` counter.
  """
  @spec generate_nonce() :: pos_integer()
  def generate_nonce do
    ref = nonce_ref()
    now = System.system_time(:millisecond)
    bump_nonce(ref, now)
  end

  defp bump_nonce(ref, now) do
    last = :atomics.get(ref, 1)
    next = max(now, last + 1)

    case :atomics.compare_exchange(ref, 1, last, next) do
      :ok -> next
      _other -> bump_nonce(ref, now)
    end
  end

  @nonce_key {__MODULE__, :nonce_ref}

  defp nonce_ref do
    case :persistent_term.get(@nonce_key, nil) do
      nil ->
        # `:persistent_term.put/2` is last-write-wins, so two racing callers
        # could otherwise end up counting on two different atomics and hand out
        # the same nonce twice. Serialize the one-off creation.
        :global.trans({@nonce_key, self()}, fn ->
          case :persistent_term.get(@nonce_key, nil) do
            nil ->
              ref = :atomics.new(1, signed: false)
              :persistent_term.put(@nonce_key, ref)
              ref

            ref ->
              ref
          end
        end)

      ref ->
        ref
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

  # ===================== Case Conversion =====================

  @doc """
  Convert struct/map to camelCase map recursively (for JSONB storage).

  Drops internal Ecto fields like :__meta__ and :id.

  ## Examples

      iex> Hyperliquid.Utils.to_camel_case_map(%{account_value: "100", total_ntl_pos: "50"})
      %{"accountValue" => "100", "totalNtlPos" => "50"}
  """
  def to_camel_case_map(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__, :id])
    |> to_camel_case_map()
  end

  def to_camel_case_map(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = k |> to_string() |> snake_to_camel()
      {key, to_camel_case_map(v)}
    end)
  end

  def to_camel_case_map(list) when is_list(list), do: Enum.map(list, &to_camel_case_map/1)
  def to_camel_case_map(value), do: value

  @doc """
  Convert snake_case string to camelCase.

  ## Examples

      iex> Hyperliquid.Utils.snake_to_camel("account_value")
      "accountValue"

      iex> Hyperliquid.Utils.snake_to_camel("total_ntl_pos")
      "totalNtlPos"
  """
  def snake_to_camel(string) do
    string
    |> String.split("_")
    |> case do
      [first | rest] -> first <> Enum.map_join(rest, &String.capitalize/1)
      [] -> ""
    end
  end
end
