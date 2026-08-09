defmodule Hyperliquid.CacheOutcomeAssetsTest do
  @moduledoc """
  HIP-4 outcome asset encoding.

  Outcome assets are absent from `spotMeta`, so `outcomeMeta` is the only source
  for them. Encoding is `outcome * 10 + side`, surfacing three ways:

      spot coin   "#<encoding>"
      token name  "+<encoding>"
      asset ID    100_000_000 + encoding

  Verified against testnet: the 309 live outcomes expand to exactly the 618
  `#`-prefixed coins that `allMids` returns, with no difference in either
  direction.
  """
  use ExUnit.Case, async: true

  alias Hyperliquid.Cache

  describe "encoding" do
    test "builds coins from outcome and side" do
      assert Cache.outcome_coin(1, 0) == "#10"
      assert Cache.outcome_coin(1, 1) == "#11"
      assert Cache.outcome_coin(7002, 0) == "#70020"
      assert Cache.outcome_coin(7002, 1) == "#70021"
    end

    test "builds asset ids from outcome and side" do
      assert Cache.outcome_asset(1, 0) == 100_000_010
      assert Cache.outcome_asset(7002, 0) == 100_070_020
      assert Cache.outcome_asset(7002, 1) == 100_070_021
    end

    test "matches the documented example" do
      # "#10 = outcome 1, side 0", asset id 100000010
      assert Cache.outcome_coin(1, 0) == "#10"
      assert Cache.outcome_asset(1, 0) == 100_000_010
      assert Cache.outcome_and_side("#10") == {:ok, {1, 0}}
      assert Cache.outcome_and_side(100_000_010) == {:ok, {1, 0}}
    end

    test "round-trips coin and asset id" do
      for outcome <- [0, 1, 7, 42, 7002, 119_38], side <- [0, 1] do
        coin = Cache.outcome_coin(outcome, side)
        asset = Cache.outcome_asset(outcome, side)

        assert Cache.outcome_and_side(coin) == {:ok, {outcome, side}}
        assert Cache.outcome_and_side(asset) == {:ok, {outcome, side}}
      end
    end

    test "rejects invalid sides" do
      assert_raise FunctionClauseError, fn -> Cache.outcome_coin(1, 2) end
      assert_raise FunctionClauseError, fn -> Cache.outcome_asset(1, -1) end
    end
  end

  describe "classification" do
    test "recognises outcome coins" do
      assert Cache.outcome_coin?("#10")
      assert Cache.outcome_coin?("#70020")
      refute Cache.outcome_coin?("BTC")
      refute Cache.outcome_coin?("HYPE/USDC")
      refute Cache.outcome_coin?("@107")
      refute Cache.outcome_coin?(nil)
    end

    test "recognises outcome asset ids without colliding with perps or spot" do
      assert Cache.outcome_asset?(100_000_000)
      assert Cache.outcome_asset?(100_070_020)

      # perps
      refute Cache.outcome_asset?(0)
      refute Cache.outcome_asset?(3)
      # spot
      refute Cache.outcome_asset?(10_000)
      refute Cache.outcome_asset?(10_107)
      # builder-deployed perps
      refute Cache.outcome_asset?(110_000)
      refute Cache.outcome_asset?(120_000)

      refute Cache.outcome_asset?("100000010")
    end

    test "outcome_and_side rejects non-outcomes" do
      assert Cache.outcome_and_side("BTC") == {:error, :not_an_outcome}
      assert Cache.outcome_and_side("#nope") == {:error, :not_an_outcome}
      assert Cache.outcome_and_side(10_107) == {:error, :not_an_outcome}
      assert Cache.outcome_and_side(nil) == {:error, :not_an_outcome}
    end

    test "the asset base is the documented constant" do
      assert Cache.outcome_asset_base() == 100_000_000
    end
  end
end
