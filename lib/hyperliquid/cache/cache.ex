defmodule Hyperliquid.Cache do
  @moduledoc """
  Application cache for storing asset lists and exchange meta information.

  This module provides functions to initialize and manage a cache for Hyperliquid-related data,
  including asset information, exchange metadata, and utility functions for retrieving and
  manipulating cached data.

  The cache is implemented using Cachex and stores various pieces of information such as:
  - Exchange metadata
  - Spot market metadata
  - Asset mappings
  - Decimal precision information
  - Token information

  It also provides utility functions for working with assets, tokens, and other cached data.
  """
  alias __MODULE__
  alias Hyperliquid.{Api.Info, Utils}

  @cache :hyperliquid

  @doc """
  Initializes the cache with api information.
  """
  def init do
    {:ok, [meta, ctxs]} = Info.meta_and_asset_ctxs()
    {:ok, [spot_meta, spot_ctxs]} = Info.spot_meta_and_asset_ctxs()
    {:ok, mids} = Info.all_mids()

    all_mids = Utils.atomize_keys(mids)
    perps = Map.get(meta, "universe")
    spot_pairs = Map.get(spot_meta, "universe")
    tokens = Map.get(spot_meta, "tokens")

    assets_name_to_coin_map = Map.merge(
        create_perp_assets_name_to_coin_map(meta),
        create_spot_assets_name_to_coin_map(spot_meta)
      )

    assets_name_to_index_map = Map.merge(
        create_perp_assets_name_to_index_map(meta),
        create_spot_assets_name_to_index_map(spot_meta)
      )

    decimal_map = Map.merge(
      create_decimal_map(meta),
      create_decimal_map(spot_meta, 8)
    )

    Cachex.put!(@cache, :meta, meta)
    Cachex.put!(@cache, :spot_meta, spot_meta)
    Cachex.put!(@cache, :all_mids, all_mids)
    Cachex.put!(@cache, :decimal_map, decimal_map)
    Cachex.put!(@cache, :perps, perps)
    Cachex.put!(@cache, :spot_pairs, spot_pairs)
    Cachex.put!(@cache, :tokens, tokens)
    Cachex.put!(@cache, :ctxs, ctxs)
    Cachex.put!(@cache, :spot_ctxs, spot_ctxs)
    Cachex.put!(@cache, :assets_name_to_index_map, assets_name_to_index_map)
    Cachex.put!(@cache, :assets_name_to_coin_map, assets_name_to_coin_map)
  end

  def meta,                         do: Cache.get(:meta)
  def spot_meta,                    do: Cache.get(:spot_meta)
  def all_mids,                     do: Cache.get(:all_mids)
  def decimal_map,                  do: Cache.get(:decimal_map)
  def perps,                        do: Cache.get(:perps)
  def spot_pairs,                   do: Cache.get(:spot_pairs)
  def tokens,                       do: Cache.get(:tokens)
  def ctxs,                         do: Cache.get(:ctxs)
  def spot_ctxs,                    do: Cache.get(:spot_ctxs)
  def assets_name_to_index_map,     do: Cache.get(:assets_name_to_index_map)
  def assets_name_to_coin_map,      do: Cache.get(:assets_name_to_coin_map)

  ###### Setters ######
  defp create_perp_assets_name_to_index_map(data) do
    perp_buffer = 0

    data
    |> Map.get("universe")
    |> Enum.with_index(&{&1["name"], &2 + perp_buffer})
    |> Enum.into(%{})
  end

  defp create_spot_assets_name_to_index_map(data) do
    spot_buffer = 10_000
    tokens = Map.get(data, "tokens")

    data
    |> Map.get("universe")
    |> Enum.reduce(%{}, fn spot_asset, spot_assets_index ->
      [base, quote] = spot_asset["tokens"]
      spot_asset_name = "#{Enum.at(tokens, base)["name"]}/#{Enum.at(tokens, quote)["name"]}"
      Map.put(spot_assets_index, spot_asset_name, spot_asset["index"] + spot_buffer)
    end)
  end

  defp create_perp_assets_name_to_coin_map(data) do
    data
    |> Map.get("universe")
    |> Enum.reduce(%{}, fn perp_assets, perp_assets_name_to_coin_map ->
      Map.put(perp_assets_name_to_coin_map, perp_assets["name"], perp_assets["name"])
    end)
  end

  defp create_spot_assets_name_to_coin_map(data) do
    tokens = Map.get(data, "tokens")

    data
    |> Map.get("universe")
    |> Enum.reduce(%{}, fn spot_asset, spot_assets_name_to_coin_map ->
      [base, quote] = spot_asset["tokens"]
      spot_asset_name = "#{Enum.at(tokens, base)["name"]}/#{Enum.at(tokens, quote)["name"]}"
      Map.put(spot_assets_name_to_coin_map, spot_asset_name, spot_asset["name"])
    end)
  end

  defp create_decimal_map(data) do
    data
    |> Map.get("universe")
    |> Enum.map(&{&1["name"], &1["szDecimals"]})
    |> Enum.into(%{})
  end

  defp create_decimal_map(data, decimals) do
    data
    |> Map.get("universe")
    |> Enum.map(&{&1["name"], decimals})
    |> Enum.into(%{})
  end

  ###### Helpers ######

  @doc """
  Retrieves the asset index for a given asset name.

  ## Parameters

  - `name`: The asset name (e.g., "BTC", "ETH" for perp assets or "PURR/USDC", "HFUN/USDC" for spot assets)

  ## Returns

  The asset index corresponding to the given asset name, or nil if not found.

  ## Example

      iex> Hyperliquid.Cache.asset_name_to_index("SOL")
      5

      iex> Hyperliquid.Cache.asset_name_to_index("PURR/USDC")
      10000
  """
  def asset_name_to_index(name), do: Cache.get(:assets_name_to_index_map)[name]
  def decimals_from_coin(coin), do: Cache.get(:decimal_map)[coin]


  @doc """
  Retrieves the coin symbol for a given asset name.

  ## Parameters

  - `name`: The asset name (e.g., "BTC", "ETH" for perp assets or "PURR/USDC", "HFUN/USDC" for spot assets)

  ## Returns

  The coin symbol corresponding to the given asset name, or nil if not found.

  ## Example

      iex> Hyperliquid.Cache.asset_name_to_coin("SOL")
      SOL

      iex> Hyperliquid.Cache.asset_name_to_coin("PURR/USDC")
      PURR/USDC

      iex> Hyperliquid.Cache.asset_name_to_coin("HFUN/USDC")
      @1
  """
  def asset_name_to_coin(name), do: Cache.get(:assets_name_to_coin_map)[name]

  def get_token_by_index(index), do:
    Cache.get(:tokens)
    |> Enum.find(& &1["index"] == index)

  def get_token_by_name(name), do:
    Cache.get(:tokens)
    |> Enum.find(& &1["name"] == name)

  def get_token_by_address(address), do:
    Cache.get(:tokens)
    |> Enum.find(& &1["tokenId"] == address)

  def get_token_name_by_index(index), do:
    get_token_by_index(index)
    |> Map.get("name")

  def get_token_key(token) when is_map(token), do: "#{Map.get(token, "name")}:#{Map.get(token, "tokenId")}"
  def get_token_key(name), do:
    name
    |> get_token_by_name()
    |> get_token_key()

  def increment, do: Cache.incr(:post_count)

  ###### Wrappers ######

  @doc """
  Retrieves a value from the cache by key.
  """
  def get(key) do
    case Cachex.get(@cache, key) do
      {:ok, value} -> value
      {:error, _reason} -> nil
    end
  end

  @doc """
  Puts a key-value pair into the cache.
  """
  def put(key, value) do
    Cachex.put!(@cache, key, value)
  end

  @doc """
  Gets a value from the cache and updates it using the provided function.
  """
  def get_and_update(key, func) do
    Cachex.get_and_update!(@cache, key, func)
  end

  def execute(func) do
    Cachex.execute!(@cache, func)
  end

  @doc """
  Executes a transaction for a set of keys.
  """
  def transaction(keys, func) do
    Cachex.transaction!(@cache, keys, func)
  end

  @doc """
  Removes a key from the cache.
  """
  def del(key) do
    Cachex.del!(@cache, key)
  end

  @doc """
  Checks if a key exists in the cache.
  """
  def exists?(key) do
    Cachex.exists?(@cache, key)
  end

  @doc """
  Increments a key's value in the cache by a given amount.
  """
  def incr(key, amount \\ 1) do
    Cachex.incr!(@cache, key, amount)
  end

  @doc """
  Decrements a key's value in the cache by a given amount.
  """
  def decr(key, amount \\ 1) do
    Cachex.decr!(@cache, key, amount)
  end

  @doc """
  Clears all entries in the cache.
  """
  def clear do
    Cachex.clear!(@cache)
  end
end
