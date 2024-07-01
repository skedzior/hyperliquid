defmodule Hyperliquid.Cache do
  alias __MODULE__
  alias Hyperliquid.Api.Info

  @cache :hyperliquid

  @doc """
  Initializes the cache with meta and spot_meta information.
  """
  def init do
    {:ok, meta} = Info.meta()
    {:ok, spot_meta} = Info.spot_meta()

    all_mids = Info.all_mids() |> elem(1) |> Hyperliquid.Atomizer.atomize_keys()
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
  Increments a key's value in the cache by a given amount.
  """
  def incr(key, amount \\ 1) do
    Cachex.incr!(@cache, key, amount)
  end

  ##### UTILS ######
  def asset_from_coin(coin), do: Cache.get(:asset_map)[coin]
  def decimals_from_coin(coin), do: Cache.get(:decimal_map)[coin]

  def get_token_by_name(name) do
    Cache.get(:tokens)
    |> Enum.find(& &1["name"] == name)
  end

  def get_token_by_address(address) do
    Cache.get(:tokens)
    |> Enum.find(& &1["tokenId"] == address)
  end

  def get_token_key(token) when is_map(token), do: "#{Map.get(token, "name")}:#{Map.get(token, "tokenId")}"
  def get_token_key(name), do:
    name
    |> get_token_by_name()
    |> get_token_key()

  def increment, do: Cache.incr(:post_count)
end
