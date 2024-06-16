defmodule Hyperliquid.Cache do
  @cache :hyperliquid

  alias Hyperliquid.Api.Info

  @doc """
  Initializes the cache with meta and spot_meta information.
  """
  def init do
    meta = Info.meta() |> elem(1)
    spot_meta = Info.spot_meta() |> elem(1)

    all_mids = Info.all_mids() |> elem(1)
    tokens = Map.get(spot_meta, "tokens")

    asset_map = Map.merge(
      create_asset_map(meta),
      create_asset_map(spot_meta, 10_000)
    )

    decimal_map = Map.merge(
      create_decimal_map(meta),
      create_decimal_map(spot_meta, 8)
    )

    Cachex.put!(@cache, :meta, meta)
    Cachex.put!(@cache, :spot_meta, spot_meta)
    Cachex.put!(@cache, :all_mids, all_mids)
    Cachex.put!(@cache, :asset_map, asset_map)
    Cachex.put!(@cache, :decimal_map, decimal_map)
    Cachex.put!(@cache, :tokens, tokens)
  end

  defp create_asset_map(data, buffer \\ 0) do
    data
    |> Map.get("universe")
    |> Enum.with_index(&{&1["name"], &2 + buffer})
    |> Enum.into(%{})
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

  @doc """
  Executes a function within the context of the cache.
  """
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
