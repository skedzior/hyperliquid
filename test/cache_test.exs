defmodule Hyperliquid.CacheTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Cache

  setup do
    on_exit(fn ->
      Cachex.del(:hyperliquid_meta, :all_mids)
      Cachex.del(:hyperliquid_meta, :all_mids_updated_at)
    end)

    :ok
  end

  describe "get_mid/1 (H14)" do
    test "parses integer-valued strings, floats and integers without raising" do
      Cache.put(:all_mids, %{
        "BTC" => "27",
        "ETH" => "27.5",
        "HYPE" => 27.5,
        "SOL" => 27,
        "JUNK" => "abc",
        "NIL" => nil
      })

      assert Cache.get_mid("BTC") == 27.0
      assert Cache.get_mid("ETH") == 27.5
      assert Cache.get_mid("HYPE") == 27.5
      assert Cache.get_mid("SOL") == 27.0
      assert Cache.get_mid("JUNK") == nil
      assert Cache.get_mid("NIL") == nil
      assert Cache.get_mid("NOT_LISTED") == nil
    end
  end

  describe "metadata isolation (H13)" do
    test "metadata keys live in the unbounded meta cache, not the firehose cache" do
      assert Cache.cache_name(:asset_map) == :hyperliquid_meta
      assert Cache.cache_name(:all_mids) == :hyperliquid_meta
      assert Cache.cache_name(:decimal_map) == :hyperliquid_meta

      # WS firehose keys stay in the size-limited cache.
      assert Cache.cache_name({:trade, "BTC", 123}) == :hyperliquid

      Cache.put(:asset_map, %{"BTC" => 0})
      assert {:ok, %{"BTC" => 0}} = Cachex.get(:hyperliquid_meta, :asset_map)
      assert {:ok, nil} = Cachex.get(:hyperliquid, :asset_map)
      assert Cache.get(:asset_map) == %{"BTC" => 0}

      Cache.del(:asset_map)
      assert Cache.get(:asset_map) == nil
    end
  end

  describe "mids staleness (H13)" do
    test "update_mids stamps a timestamp that mids_stale?/1 reads" do
      Cache.update_mids(%{"BTC" => "50000"})

      assert is_integer(Cache.mids_age_ms())
      refute Cache.mids_stale?(60_000)
      assert Cache.mids_stale?(-1)
    end

    test "mids of unknown age are considered stale" do
      Cachex.del(:hyperliquid_meta, :all_mids_updated_at)
      assert Cache.mids_age_ms() == nil
      assert Cache.mids_stale?(60_000)
    end
  end

  describe "refresh interval (H13)" do
    test "reads the configured interval" do
      assert Cache.refresh_interval() == 300_000

      Application.put_env(:hyperliquid, :cache_refresh_interval, 1234)
      assert Cache.refresh_interval() == 1234
      Application.delete_env(:hyperliquid, :cache_refresh_interval)
    end
  end
end
