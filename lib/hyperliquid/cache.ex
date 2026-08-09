defmodule Hyperliquid.Cache do
  @moduledoc """
  Application cache for storing asset lists and exchange meta information.

  This module provides functions to initialize and manage a cache for Hyperliquid-related data,
  including asset information, exchange metadata, mid prices, and utility functions for retrieving
  and manipulating cached data.

  The cache is implemented using Cachex and stores:
  - Exchange metadata (perps and spot)
  - Asset mappings (coin name -> asset index)
  - Decimal precision information
  - Current mid prices (from allMids)
  - Token information

  ## Usage

      # Initialize cache with API data
      Hyperliquid.Cache.init()

      # Get mid price for a coin
      Hyperliquid.Cache.get_mid("BTC")
      # => 43250.5

      # Get asset index for a coin
      Hyperliquid.Cache.asset_from_coin("BTC")
      # => 0

      # Update mid prices (typically from WebSocket subscription)
      Hyperliquid.Cache.update_mids(%{"BTC" => "43250.5", "ETH" => "2250.0"})

      # Subscribe to live mid price updates via WebSocket
      Hyperliquid.Cache.subscribe_to_mids()
  """

  require Logger

  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http

  @cache :hyperliquid

  # Refresh interval for periodic cache refresh (5 minutes)
  @refresh_interval 300_000

  # ===================== Initialization =====================

  @doc """
  Initializes the cache with API information.

  Fetches metadata for perps and spot markets, asset mappings, and current mid prices.
  This should be called at application startup.

  This is a backwards-compatible wrapper around init_with_partial_success/0.
  Partial successes are treated as full successes for callers that don't need
  to know which keys failed.
  """
  def init do
    case init_with_partial_success() do
      :ok -> :ok
      {:ok, :partial, _failed_keys} -> :ok
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Initializes the cache with partial failure handling.

  Fetches all 4 data sources (meta, spot_meta, mids, perp_dexs) and stores
  only the successful results. Failed fetches are SKIPPED, not stored.

  ## Returns

  - `:ok` - All 4 sources fetched successfully
  - `{:ok, :partial, failed_keys}` - Some sources failed, `failed_keys` is a list
    of atoms like `[:mids, :perp_dexs]` indicating which fetches failed
  - `{:error, :all_failed}` - All 4 sources failed to fetch

  ## Example

      Hyperliquid.Cache.init_with_partial_success()
      # => :ok

      # If mids API is down:
      Hyperliquid.Cache.init_with_partial_success()
      # => {:ok, :partial, [:mids]}
  """
  def init_with_partial_success do
    cache_init_start = System.monotonic_time()
    debug("Cache.init_with_partial_success starting...")

    # Fetch all data sources. outcome_meta is the only source for HIP-4 outcome
    # assets — they do not appear in spotMeta.
    fetches = [
      {:meta, fn -> Http.meta_and_asset_ctxs() end},
      {:spot_meta, fn -> Http.spot_meta_and_asset_ctxs() end},
      {:mids, fn -> Http.all_mids(raw: true) end},
      {:perp_dexs, fn -> Http.perp_dexs() end},
      {:outcome_meta, fn -> Http.outcome_meta(raw: true) end}
    ]

    results =
      Enum.map(fetches, fn {key, fetch_fn} ->
        result = fetch_fn.()
        debug("Fetched #{key}", %{success: match?({:ok, _}, result)})
        {key, result}
      end)

    {successes, failures} =
      Enum.split_with(results, fn {_key, result} ->
        match?({:ok, _}, result)
      end)

    failed_keys = Enum.map(failures, fn {key, _result} -> key end)

    debug("Fetch results", %{
      success_count: length(successes),
      failure_count: length(failures),
      failed_keys: failed_keys
    })

    # Process and store successful fetches
    success_map = Map.new(successes, fn {key, {:ok, data}} -> {key, data} end)

    if map_size(success_map) > 0 do
      store_successful_fetches(success_map)
    end

    # Return appropriate result based on success/failure counts. Counted against
    # the number of fetches rather than a literal, so adding a source does not
    # silently turn a full success into a reported partial one.
    total_fetches = length(fetches)

    result =
      case {length(successes), length(failures)} do
        {^total_fetches, 0} ->
          debug("Cache.init_with_partial_success completed successfully")
          :ok

        {n, _} when n > 0 ->
          debug("Cache.init_with_partial_success completed with partial failures", %{
            failed_keys: failed_keys
          })

          {:ok, :partial, failed_keys}

        {0, _} ->
          debug("Cache.init_with_partial_success failed - all fetches failed")
          {:error, :all_failed}
      end

    duration = System.monotonic_time() - cache_init_start

    case result do
      {:error, reason} ->
        :telemetry.execute(
          [:hyperliquid, :cache, :init, :exception],
          %{duration: duration},
          %{reason: reason}
        )

      _ ->
        :telemetry.execute(
          [:hyperliquid, :cache, :init, :stop],
          %{duration: duration},
          %{}
        )
    end

    result
  end

  # Store successful fetches into cache
  defp store_successful_fetches(success_map) do
    # Extract data from success map
    meta_data = Map.get(success_map, :meta)
    spot_meta_data = Map.get(success_map, :spot_meta)
    mids_data = Map.get(success_map, :mids)
    perp_dexs_data = Map.get(success_map, :perp_dexs)

    # Process meta if available
    {perp_asset_map, perp_decimal_map, base_meta, ctxs, dex_offsets, perp_meta_by_dex,
     margin_tables} =
      if meta_data && perp_dexs_data do
        [base_meta, ctxs] = meta_data

        debug("Processing perp meta", %{
          universe_count: length(Map.get(base_meta, "universe", []))
        })

        # Discover builder-deployed perp DEXs and compute offsets
        builder_dexs =
          perp_dexs_data
          |> extract_builder_dexs()
          |> maybe_limit_testnet_dexs()

        debug("Builder DEXs", %{dexs: builder_dexs, count: length(builder_dexs)})

        dex_offsets =
          builder_dexs
          |> Enum.with_index()
          |> Enum.reduce(%{"" => 0}, fn {dex, i}, acc ->
            Map.put(acc, dex, 110_000 + i * 10_000)
          end)

        debug("DEX offsets", %{offsets: dex_offsets})

        # Fetch meta for each builder perp DEX
        perp_meta_by_dex =
          builder_dexs
          |> Enum.map(fn dex ->
            case Http.all_perp_metas(dex) do
              {:ok, meta} ->
                debug("Fetched meta for DEX", %{
                  dex: dex,
                  universe_count: length(Map.get(meta, "universe", []))
                })

                {dex, meta}

              {:error, _} ->
                debug("Failed to fetch meta for DEX", %{dex: dex})
                {dex, %{"universe" => []}}
            end
          end)
          |> Enum.into(%{})

        # Build asset + decimals maps starting with base perps
        {perp_asset_map, perp_decimal_map} = build_perp_maps(base_meta, 0, %{}, %{})

        # Add builder DEX perps
        {perp_asset_map, perp_decimal_map} =
          Enum.reduce(perp_meta_by_dex, {perp_asset_map, perp_decimal_map}, fn {dex, meta},
                                                                               {am, dm} ->
            offset = Map.fetch!(dex_offsets, dex)
            build_perp_maps(meta, offset, am, dm)
          end)

        debug("Built perp maps", %{
          asset_map_count: map_size(perp_asset_map),
          decimal_map_count: map_size(perp_decimal_map)
        })

        # Margin tables to map id => table
        margin_tables = margin_tables_to_map(base_meta)

        {perp_asset_map, perp_decimal_map, base_meta, ctxs, dex_offsets, perp_meta_by_dex,
         margin_tables}
      else
        {%{}, %{}, nil, nil, nil, nil, nil}
      end

    # Process spot meta if available
    {spot_asset_map, spot_decimal_map, spot_meta, spot_ctxs} =
      if spot_meta_data do
        [spot_meta, spot_ctxs] = spot_meta_data

        debug("Processing spot meta", %{
          universe_count: length(Map.get(spot_meta, "universe", []))
        })

        {spot_asset_map, spot_decimal_map} = build_spot_maps(spot_meta)
        {spot_asset_map, spot_decimal_map, spot_meta, spot_ctxs}
      else
        {%{}, %{}, nil, nil}
      end

    # Process HIP-4 outcome meta if available. Outcome assets are absent from
    # spotMeta, so without this they cannot be resolved at all.
    outcome_meta_data = Map.get(success_map, :outcome_meta)

    {outcome_asset_map, outcome_decimal_map} =
      if outcome_meta_data do
        {map, decimals} = build_outcome_maps(outcome_meta_data)

        debug("Processing outcome meta", %{outcome_assets: map_size(map)})

        {map, decimals}
      else
        {%{}, %{}}
      end

    # Merge maps
    asset_map = perp_asset_map |> Map.merge(spot_asset_map) |> Map.merge(outcome_asset_map)

    decimal_map =
      perp_decimal_map |> Map.merge(spot_decimal_map) |> Map.merge(outcome_decimal_map)

    debug("Merged maps", %{
      total_assets: map_size(asset_map),
      total_decimals: map_size(decimal_map)
    })

    # Map asset_id -> szDecimals and asset_id -> allowed price decimals
    asset_to_sz_decimals =
      Enum.reduce(asset_map, %{}, fn {name, asset}, acc ->
        Map.put(acc, asset, Map.get(decimal_map, name))
      end)

    asset_to_price_decimals =
      Enum.reduce(asset_to_sz_decimals, %{}, fn {asset, sz_dec}, acc ->
        max_decimals = max_decimals_for_asset(asset)
        allowed = max(max_decimals - (sz_dec || 0), 0)
        Map.put(acc, asset, allowed)
      end)

    # Store meta-related data (only if we have it)
    if base_meta do
      cache_put(:perp_meta, base_meta)
      cache_put(:perp_meta_by_dex, perp_meta_by_dex)
      cache_put(:dex_offsets, dex_offsets)
      cache_put(:margin_tables, margin_tables)
      cache_put(:perps, Map.get(base_meta, "universe", []))
      cache_put(:ctxs, ctxs)
    end

    # Store spot-related data
    if spot_meta do
      cache_put(:spot_meta, spot_meta)
      cache_put(:spot_pairs, Map.get(spot_meta, "universe", []))
      cache_put(:tokens, Map.get(spot_meta, "tokens", []))
      cache_put(:spot_ctxs, spot_ctxs)

      # Build spot pair mappings (BASE/QUOTE format)
      {spot_pair_asset_map, spot_pair_id_map, spot_pair_decimals} =
        build_spot_pair_maps(spot_meta)

      cache_put(:spot_pair_asset_map, spot_pair_asset_map)
      cache_put(:spot_pair_id_map, spot_pair_id_map)
      cache_put(:spot_pair_decimals, spot_pair_decimals)
    end

    # Store mids if available
    if mids_data do
      debug("Storing mids", %{mids_count: map_size(mids_data)})
      cache_put(:all_mids, mids_data)
    end

    # Store combined maps (only if we have any data)
    if map_size(asset_map) > 0 do
      cache_put(:asset_map, asset_map)
      cache_put(:decimal_map, decimal_map)
      cache_put(:asset_to_sz_decimals, asset_to_sz_decimals)
      cache_put(:asset_to_price_decimals, asset_to_price_decimals)
    end

    :ok
  end

  # Simple cache put without TTL - entries persist until manually updated or cleared
  defp cache_put(key, value) do
    case Cachex.put(@cache, key, value) do
      {:ok, true} ->
        :ok

      {:error, reason} ->
        Logger.warning("[Cache] Failed to store #{inspect(key)}", error: inspect(reason))
        :error
    end
  end

  @doc false
  # Legacy init implementation - kept for reference but no longer used
  def init_legacy do
    debug("Cache.init starting...")

    with {:ok, [base_meta, ctxs]} <- Http.meta_and_asset_ctxs(),
         _ <-
           debug("Fetched base perp meta", %{
             universe_count: length(Map.get(base_meta, "universe", []))
           }),
         {:ok, [spot_meta, spot_ctxs]} <- Http.spot_meta_and_asset_ctxs(),
         _ <-
           debug("Fetched spot meta", %{
             universe_count: length(Map.get(spot_meta, "universe", []))
           }),
         {:ok, mids} <- Http.all_mids(raw: true),
         _ <- debug("Fetched all mids", %{mids_count: map_size(mids)}),
         {:ok, perp_dexs_resp} <- Http.perp_dexs(),
         _ <- debug("Fetched perp DEXs") do
      # Discover builder-deployed perp DEXs and compute offsets
      builder_dexs =
        perp_dexs_resp
        |> extract_builder_dexs()
        |> maybe_limit_testnet_dexs()

      debug("Builder DEXs", %{dexs: builder_dexs, count: length(builder_dexs)})

      dex_offsets =
        builder_dexs
        |> Enum.with_index()
        |> Enum.reduce(%{"" => 0}, fn {dex, i}, acc ->
          Map.put(acc, dex, 110_000 + i * 10_000)
        end)

      debug("DEX offsets", %{offsets: dex_offsets})

      # Fetch meta for each builder perp DEX
      perp_meta_by_dex =
        builder_dexs
        |> Enum.map(fn dex ->
          case Http.all_perp_metas(dex) do
            {:ok, meta} ->
              debug("Fetched meta for DEX", %{
                dex: dex,
                universe_count: length(Map.get(meta, "universe", []))
              })

              {dex, meta}

            {:error, _} ->
              debug("Failed to fetch meta for DEX", %{dex: dex})
              {dex, %{"universe" => []}}
          end
        end)
        |> Enum.into(%{})

      # Build asset + decimals maps starting with base perps
      {perp_asset_map, perp_decimal_map} = build_perp_maps(base_meta, 0, %{}, %{})

      # Add builder DEX perps
      {perp_asset_map, perp_decimal_map} =
        Enum.reduce(perp_meta_by_dex, {perp_asset_map, perp_decimal_map}, fn {dex, meta},
                                                                             {am, dm} ->
          offset = Map.fetch!(dex_offsets, dex)
          build_perp_maps(meta, offset, am, dm)
        end)

      debug("Built perp maps", %{
        asset_map_count: map_size(perp_asset_map),
        decimal_map_count: map_size(perp_decimal_map)
      })

      {spot_asset_map, spot_decimal_map} = build_spot_maps(spot_meta)

      asset_map = Map.merge(perp_asset_map, spot_asset_map)
      decimal_map = Map.merge(perp_decimal_map, spot_decimal_map)

      debug("Merged maps", %{
        total_assets: map_size(asset_map),
        total_decimals: map_size(decimal_map)
      })

      # Map asset_id -> szDecimals and asset_id -> allowed price decimals
      asset_to_sz_decimals =
        Enum.reduce(asset_map, %{}, fn {name, asset}, acc ->
          Map.put(acc, asset, Map.get(decimal_map, name))
        end)

      asset_to_price_decimals =
        Enum.reduce(asset_to_sz_decimals, %{}, fn {asset, sz_dec}, acc ->
          max_decimals = max_decimals_for_asset(asset)
          allowed = max(max_decimals - (sz_dec || 0), 0)
          Map.put(acc, asset, allowed)
        end)

      # Margin tables to map id => table
      margin_tables = margin_tables_to_map(base_meta)

      # Store mids with original string keys (no transformation)
      debug("Storing mids", %{mids_count: map_size(mids)})

      # Store all data (no TTL - entries persist until updated)
      cache_put(:perp_meta, base_meta)
      cache_put(:perp_meta_by_dex, perp_meta_by_dex)
      cache_put(:dex_offsets, dex_offsets)
      cache_put(:margin_tables, margin_tables)
      cache_put(:spot_meta, spot_meta)
      cache_put(:all_mids, mids)
      cache_put(:asset_map, asset_map)
      cache_put(:decimal_map, decimal_map)
      cache_put(:asset_to_sz_decimals, asset_to_sz_decimals)
      cache_put(:asset_to_price_decimals, asset_to_price_decimals)
      cache_put(:perps, Map.get(base_meta, "universe", []))
      cache_put(:spot_pairs, Map.get(spot_meta, "universe", []))
      cache_put(:tokens, Map.get(spot_meta, "tokens", []))
      cache_put(:ctxs, ctxs)
      cache_put(:spot_ctxs, spot_ctxs)

      # Build spot pair mappings (BASE/QUOTE format)
      {spot_pair_asset_map, spot_pair_id_map, spot_pair_decimals} =
        build_spot_pair_maps(spot_meta)

      cache_put(:spot_pair_asset_map, spot_pair_asset_map)
      cache_put(:spot_pair_id_map, spot_pair_id_map)
      cache_put(:spot_pair_decimals, spot_pair_decimals)

      debug("Cache.init completed successfully")
      :ok
    else
      {:error, reason} = error ->
        debug("Cache.init failed", %{error: reason})
        error
    end
  end

  defp debug(message, data \\ nil) do
    if Config.debug?() do
      Logger.debug("[Cache] #{message}", data: data)
    end

    :ok
  end

  # ===================== Getters =====================

  @doc "Get perpetuals metadata (base DEX)"
  def perp_meta, do: get(:perp_meta)

  @doc "Get perpetuals metadata by DEX name"
  def perp_meta_by_dex, do: get(:perp_meta_by_dex)

  @doc "Get DEX name to asset offset mapping"
  def dex_offsets, do: get(:dex_offsets)

  @doc "Get margin tables (id => table)"
  def margin_tables, do: get(:margin_tables)

  @doc "Get spot market metadata"
  def spot_meta, do: get(:spot_meta)

  @doc "Get all mid prices as string-keyed map (original API format)"
  def all_mids, do: get(:all_mids)

  @doc "Get asset name -> asset index map"
  def asset_map, do: get(:asset_map)

  @doc "Get asset name -> decimal precision map"
  def decimal_map, do: get(:decimal_map)

  @doc "Get asset index -> size decimals map"
  def asset_to_sz_decimals_map, do: get(:asset_to_sz_decimals)

  @doc "Get asset index -> price decimals map"
  def asset_to_price_decimals_map, do: get(:asset_to_price_decimals)

  @doc "Get list of perp universe entries"
  def perps, do: get(:perps)

  @doc "Get list of spot pair entries"
  def spot_pairs, do: get(:spot_pairs)

  @doc "Get list of token entries"
  def tokens, do: get(:tokens)

  @doc "Get perp asset contexts"
  def ctxs, do: get(:ctxs)

  @doc "Get spot asset contexts"
  def spot_ctxs, do: get(:spot_ctxs)

  # ===================== Helpers =====================

  @doc """
  Get the mid price for a coin.

  ## Parameters
    - `coin`: Coin symbol as string (e.g., "BTC", "ETH")

  ## Returns
    - Float mid price, or nil if not found

  ## Example

      Hyperliquid.Cache.get_mid("BTC")
      # => 43250.5
  """
  def get_mid(coin) when is_binary(coin) do
    case get(:all_mids) do
      nil ->
        nil

      mids ->
        case Map.get(mids, coin) do
          nil -> nil
          price when is_binary(price) -> String.to_float(price)
          price when is_float(price) -> price
        end
    end
  end

  # ===================== HIP-4 outcome assets =====================

  # Outcome assets are derived from an outcome id plus a binary side, encoded as
  # `outcome * 10 + side`. The same encoding appears three ways:
  #
  #   spot coin   "#<encoding>"
  #   token name  "+<encoding>"
  #   asset ID    100_000_000 + encoding
  #
  # See https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids
  @outcome_asset_base 100_000_000

  @doc """
  The asset ID base for HIP-4 outcome assets.
  """
  @spec outcome_asset_base() :: pos_integer()
  def outcome_asset_base, do: @outcome_asset_base

  @doc """
  Whether an asset ID refers to a HIP-4 outcome asset.

  ## Example

      Hyperliquid.Cache.outcome_asset?(100_070_020)
      # => true
  """
  @spec outcome_asset?(term()) :: boolean()
  def outcome_asset?(asset) when is_integer(asset), do: asset >= @outcome_asset_base
  def outcome_asset?(_), do: false

  @doc """
  Whether a coin string refers to a HIP-4 outcome asset.

  ## Example

      Hyperliquid.Cache.outcome_coin?("#70020")
      # => true
  """
  @spec outcome_coin?(term()) :: boolean()
  def outcome_coin?(coin) when is_binary(coin), do: String.starts_with?(coin, "#")
  def outcome_coin?(_), do: false

  @doc """
  Build the coin string for an outcome id and side.

  Only sides `0` and `1` are valid.

  ## Example

      Hyperliquid.Cache.outcome_coin(7002, 0)
      # => "#70020"
  """
  @spec outcome_coin(non_neg_integer(), 0 | 1) :: String.t()
  def outcome_coin(outcome, side) when is_integer(outcome) and side in [0, 1] do
    "#" <> Integer.to_string(outcome_encoding(outcome, side))
  end

  @doc """
  Build the asset ID for an outcome id and side.

  ## Example

      Hyperliquid.Cache.outcome_asset(7002, 0)
      # => 100070020
  """
  @spec outcome_asset(non_neg_integer(), 0 | 1) :: pos_integer()
  def outcome_asset(outcome, side) when is_integer(outcome) and side in [0, 1] do
    @outcome_asset_base + outcome_encoding(outcome, side)
  end

  @doc """
  Recover `{outcome, side}` from an outcome coin or asset ID.

  ## Returns
    - `{:ok, {outcome, side}}`
    - `{:error, :not_an_outcome}`

  ## Example

      Hyperliquid.Cache.outcome_and_side("#70020")
      # => {:ok, {7002, 0}}
  """
  @spec outcome_and_side(String.t() | integer()) ::
          {:ok, {non_neg_integer(), 0 | 1}} | {:error, :not_an_outcome}
  def outcome_and_side("#" <> encoding) do
    case Integer.parse(encoding) do
      {value, ""} -> {:ok, {div(value, 10), rem(value, 10)}}
      _ -> {:error, :not_an_outcome}
    end
  end

  def outcome_and_side(asset) when is_integer(asset) and asset >= @outcome_asset_base do
    encoding = asset - @outcome_asset_base
    {:ok, {div(encoding, 10), rem(encoding, 10)}}
  end

  def outcome_and_side(_), do: {:error, :not_an_outcome}

  defp outcome_encoding(outcome, side), do: outcome * 10 + side

  # Outcomes trade like spot, so they take the spot price-decimal ceiling rather
  # than the perp one.
  defp max_decimals_for_asset(asset) do
    cond do
      outcome_asset?(asset) -> 8
      asset >= 10_000 and asset < 100_000 -> 8
      true -> 6
    end
  end

  # Outcome assets take whole-number sizes only. Confirmed on testnet against
  # asset 100102190: sizes of 1000 and 1001 passed validation, while 1000.5 and
  # 1000.05 were both rejected with "Order has invalid size."
  #
  # No endpoint publishes this — outcomeMeta omits szDecimals and outcome tokens
  # are absent from spotMeta — so it stays configurable in case it varies per
  # outcome or changes on a network upgrade.
  defp outcome_sz_decimals do
    Application.get_env(:hyperliquid, :outcome_sz_decimals, 0)
  end

  defp build_outcome_maps(outcome_meta) do
    outcomes = Map.get(outcome_meta, "outcomes") || Map.get(outcome_meta, :outcomes) || []
    sz_decimals = outcome_sz_decimals()

    Enum.reduce(outcomes, {%{}, %{}}, fn outcome, {assets, decimals} ->
      id = Map.get(outcome, "outcome") || Map.get(outcome, :outcome)

      if is_integer(id) do
        Enum.reduce(0..1, {assets, decimals}, fn side, {a, d} ->
          coin = outcome_coin(id, side)
          {Map.put(a, coin, outcome_asset(id, side)), Map.put(d, coin, sz_decimals)}
        end)
      else
        {assets, decimals}
      end
    end)
  end

  @doc """
  Get the asset index for a coin symbol.

  Supports multiple formats:
  - Perp: "BTC" → 0
  - Spot pair: "HYPE/USDC" → 10107
  - Plain coin name: "BTC" → 0

  ## Parameters
    - `coin`: Coin symbol (e.g., "BTC", "HYPE/USDC")

  ## Returns
    - Asset index as integer, or nil if not found

  ## Example

      Hyperliquid.Cache.asset_from_coin("BTC")
      # => 0

      Hyperliquid.Cache.asset_from_coin("HYPE/USDC")
      # => 10107
  """
  def asset_from_coin(coin) do
    # Try spot pair format first if it contains "/"
    if String.contains?(coin, "/") do
      case get(:spot_pair_asset_map) do
        nil -> nil
        map -> Map.get(map, coin)
      end
    else
      case get(:asset_map) do
        nil -> nil
        map -> Map.get(map, coin)
      end
    end
  end

  @doc """
  Get the spot pair ID for info endpoints and subscriptions.

  Accepts spot markets in "BASE/QUOTE" format (e.g., "HYPE/USDC").
  Returns the pair ID used in l2book, trades, etc.

  ## Example

      Hyperliquid.Cache.spot_pair_id("HFUN/USDC")
      # => "@2"

      Hyperliquid.Cache.spot_pair_id("PURR/USDC")
      # => "PURR/USDC"
  """
  def spot_pair_id(pair) do
    case get(:spot_pair_id_map) do
      nil -> nil
      map -> Map.get(map, pair)
    end
  end

  @doc """
  Get size decimals for a spot pair in BASE/QUOTE format.

  ## Example

      Hyperliquid.Cache.spot_pair_decimals("HYPE/USDC")
      # => 2
  """
  def spot_pair_decimals(pair) do
    case get(:spot_pair_decimals) do
      nil -> nil
      map -> Map.get(map, pair)
    end
  end

  @doc """
  Get the coin symbol for an asset index (reverse lookup).

  ## Parameters
    - `asset`: Asset index as integer

  ## Returns
    - Coin symbol as string, or nil if not found

  ## Example

      Hyperliquid.Cache.coin_from_asset(0)
      # => "BTC"
  """
  def coin_from_asset(asset) when is_integer(asset) do
    if asset >= 10_000 and asset < 100_000 do
      case get(:spot_pair_asset_map) do
        nil -> nil
        map -> find_key_by_value(map, asset)
      end
    else
      case get(:asset_map) do
        nil -> nil
        map -> find_key_by_value(map, asset)
      end
    end
  end

  defp find_key_by_value(map, value) do
    Enum.find_value(map, fn {k, v} -> if v == value, do: k end)
  end

  def decimals_from_coin(coin) do
    case get(:decimal_map) do
      nil -> nil
      map -> Map.get(map, coin)
    end
  end

  @doc """
  Get size decimals by asset index.
  """
  def sz_decimals_by_asset(asset) do
    case get(:asset_to_sz_decimals) do
      nil -> nil
      map -> Map.get(map, asset)
    end
  end

  @doc """
  Get price decimals by asset index.
  """
  def price_decimals_by_asset(asset) do
    case get(:asset_to_price_decimals) do
      nil -> nil
      map -> Map.get(map, asset)
    end
  end

  @doc """
  Get token info by index.
  """
  def get_token_by_index(index) do
    case get(:tokens) do
      nil -> nil
      tokens -> Enum.find(tokens, &(&1["index"] == index))
    end
  end

  @doc """
  Get token info by name.
  """
  def get_token_by_name(name) do
    case get(:tokens) do
      nil -> nil
      tokens -> Enum.find(tokens, &(&1["name"] == name))
    end
  end

  @doc """
  Get token key in format "NAME:token_id".
  """
  def get_token_key(token) when is_map(token) do
    # HTTP module transforms tokenId -> token_id
    "#{Map.get(token, "name")}:#{Map.get(token, "token_id")}"
  end

  def get_token_key(name) when is_binary(name) do
    case get_token_by_name(name) do
      nil -> nil
      token -> get_token_key(token)
    end
  end

  # ===================== Setters =====================

  @doc """
  Update mid prices in cache.

  ## Parameters
    - `mids`: Map of coin symbol to price (can have string or atom keys)

  ## Example

      Hyperliquid.Cache.update_mids(%{"BTC" => "43250.5", "ETH" => "2250.0"})
  """
  def update_mids(mids) when is_map(mids) do
    merged_mids =
      case get(:all_mids) do
        nil -> mids
        existing -> Map.merge(existing, mids)
      end

    cache_put(:all_mids, merged_mids)
  end

  @doc """
  Update a single mid price.

  ## Parameters
    - `coin`: Coin symbol as string
    - `price`: Price as string or number
  """
  def update_mid(coin, price) when is_binary(coin) do
    updated_mids =
      case get(:all_mids) do
        nil -> %{coin => price}
        existing -> Map.put(existing, coin, price)
      end

    cache_put(:all_mids, updated_mids)
  end

  # ===================== WebSocket Subscription =====================

  @doc """
  Subscribe to live mid price updates via WebSocket.

  This creates a WebSocket subscription to the allMids channel which
  provides real-time price updates for all assets. The cache will be
  automatically updated as new prices arrive.

  ## Returns
    - `{:ok, subscription_id}` - Subscription created successfully
    - `{:error, reason}` - Failed to subscribe

  ## Example

      {:ok, sub_id} = Hyperliquid.Cache.subscribe_to_mids()
  """
  def subscribe_to_mids do
    alias Hyperliquid.WebSocket.Manager
    alias Hyperliquid.Api.Subscription.AllMids

    callback = fn message ->
      handle_mids_message(message)
    end

    Manager.subscribe(AllMids, %{}, callback)
  end

  @doc """
  Unsubscribe from live mid price updates.

  ## Parameters
    - `subscription_id`: The subscription ID returned from subscribe_to_mids/0
  """
  def unsubscribe_from_mids(subscription_id) do
    Hyperliquid.WebSocket.Manager.unsubscribe(subscription_id)
  end

  @doc """
  Schedule periodic refresh of cache metadata.

  This sets up a timer to periodically refresh exchange metadata
  (perps, spots, tokens) to pick up any new listings.

  ## Options
    - `:interval` - Refresh interval in milliseconds (default: #{@refresh_interval}ms)

  ## Returns
    - `{:ok, timer_ref}` - Timer scheduled successfully
  """
  def schedule_refresh(opts \\ []) do
    interval = Keyword.get(opts, :interval, @refresh_interval)
    {:ok, Process.send_after(self(), :refresh_cache, interval)}
  end

  # Handle incoming WebSocket messages for allMids
  defp handle_mids_message(%{"channel" => "allMids", "data" => %{"mids" => mids}}) do
    update_mids(mids)
    :ok
  end

  defp handle_mids_message(_other), do: :ok

  @doc """
  Get margin table by ID.

  ## Example

      Hyperliquid.Cache.get_margin_table(56)
      # => %{"description" => "tiered 40x", ...}
  """
  def get_margin_table(table_id) do
    case get(:margin_tables) do
      nil -> nil
      tables -> Map.get(tables, table_id)
    end
  end

  @doc """
  Get perp info by asset index.

  Returns the perp universe entry for a given asset index.
  Searches across all DEXs.
  """
  def get_perp_by_asset(asset) when is_integer(asset) do
    cond do
      asset < 100_000 ->
        case get(:perps) do
          nil -> nil
          perps -> Enum.at(perps, asset)
        end

      true ->
        case get(:perp_meta_by_dex) do
          nil ->
            nil

          meta_by_dex ->
            case get(:dex_offsets) do
              nil ->
                nil

              offsets ->
                Enum.find_value(offsets, fn {dex, offset} ->
                  if asset >= offset and asset < offset + 10_000 do
                    meta = Map.get(meta_by_dex, dex, %{})
                    universe = Map.get(meta, "universe", [])
                    Enum.at(universe, asset - offset)
                  end
                end)
            end
        end
    end
  end

  @doc """
  Get spot pair info by asset index.

  Returns the spot universe entry for a given asset index.
  """
  def get_spot_by_asset(asset) when is_integer(asset) and asset >= 10_000 and asset < 100_000 do
    spot_index = asset - 10_000

    case get(:spot_pairs) do
      nil -> nil
      pairs -> Enum.at(pairs, spot_index)
    end
  end

  def get_spot_by_asset(_), do: nil

  @doc """
  Query perp or spot info by name or asset index.

  ## Examples

      Hyperliquid.Cache.query_asset("BTC")
      # => %{type: :perp, asset: 0, name: "BTC", sz_decimals: 5, ...}

      Hyperliquid.Cache.query_asset("HYPE/USDC")
      # => %{type: :spot, asset: 10107, name: "@107", tokens: [107, 0], ...}

      Hyperliquid.Cache.query_asset(0)
      # => %{type: :perp, asset: 0, name: "BTC", sz_decimals: 5, ...}
  """
  def query_asset(name) when is_binary(name) do
    case asset_from_coin(name) do
      nil -> nil
      asset -> query_asset(asset)
    end
  end

  def query_asset(asset) when is_integer(asset) do
    cond do
      outcome_asset?(asset) ->
        case outcome_and_side(asset) do
          {:ok, {outcome, side}} ->
            %{
              type: :outcome,
              asset: asset,
              coin: outcome_coin(outcome, side),
              outcome: outcome,
              side: side,
              sz_decimals: sz_decimals_by_asset(asset),
              price_decimals: price_decimals_by_asset(asset)
            }

          _ ->
            nil
        end

      asset >= 10_000 and asset < 100_000 ->
        case get_spot_by_asset(asset) do
          nil ->
            nil

          info ->
            %{
              type: :spot,
              asset: asset,
              info: info,
              sz_decimals: sz_decimals_by_asset(asset),
              price_decimals: price_decimals_by_asset(asset)
            }
        end

      true ->
        case get_perp_by_asset(asset) do
          nil ->
            nil

          info ->
            margin_table = get_margin_table(info["margin_table_id"])

            %{
              type: :perp,
              asset: asset,
              info: info,
              sz_decimals: sz_decimals_by_asset(asset),
              price_decimals: price_decimals_by_asset(asset),
              margin_table: margin_table,
              max_leverage: info["max_leverage"]
            }
        end
    end
  end

  # ===================== Private Helpers =====================

  # Limit builder DEXs to first 10 on testnet to avoid rate limiting
  defp maybe_limit_testnet_dexs(dexs) do
    if Config.mainnet?() do
      dexs
    else
      limited = Enum.take(dexs, 10)
      debug("Limiting testnet DEXs", %{total: length(dexs), limited_to: length(limited)})
      limited
    end
  end

  defp extract_builder_dexs(perp_dexs_resp) do
    dex_list =
      cond do
        is_list(perp_dexs_resp) ->
          perp_dexs_resp

        is_map(perp_dexs_resp) and is_list(perp_dexs_resp["perp_dexs"]) ->
          perp_dexs_resp["perp_dexs"]

        true ->
          []
      end

    dex_list
    |> Enum.map(fn
      %{"name" => name} -> name
      %{:name => name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp margin_tables_to_map(meta) do
    case Map.get(meta, "margin_tables") do
      list when is_list(list) ->
        Enum.into(list, %{}, fn [id, table] -> {id, table} end)

      _ ->
        %{}
    end
  end

  defp build_perp_maps(meta, offset, asset_map_acc, decimal_map_acc) do
    meta
    |> Map.get("universe", [])
    |> Enum.with_index()
    |> Enum.reduce({asset_map_acc, decimal_map_acc}, fn {asset_info, idx}, {am, dm} ->
      name = asset_info["name"]
      asset_id = offset + idx
      # HTTP module transforms szDecimals -> sz_decimals
      sz_decimals = asset_info["sz_decimals"]
      {Map.put(am, name, asset_id), Map.put(dm, name, sz_decimals)}
    end)
  end

  defp build_spot_maps(spot_meta) do
    tokens = Map.get(spot_meta, "tokens", [])
    token_by_index = Enum.into(tokens, %{}, fn t -> {t["index"], t} end)

    spot_meta
    |> Map.get("universe", [])
    |> Enum.reduce({%{}, %{}}, fn spot_info, {am, dm} ->
      name = spot_info["name"]
      base_index = (spot_info["tokens"] || []) |> Enum.at(0)
      base_token = Map.get(token_by_index, base_index, %{})
      # HTTP module transforms szDecimals -> sz_decimals
      base_sz_decimals = Map.get(base_token, "sz_decimals", 8)
      asset_id = 10_000 + spot_info["index"]
      {Map.put(am, name, asset_id), Map.put(dm, name, base_sz_decimals)}
    end)
  end

  # Build spot pair maps with BASE/QUOTE format keys
  defp build_spot_pair_maps(spot_meta) do
    tokens = Map.get(spot_meta, "tokens", [])
    token_by_index = Enum.into(tokens, %{}, fn t -> {t["index"], t} end)

    spot_meta
    |> Map.get("universe", [])
    |> Enum.reduce({%{}, %{}, %{}}, fn spot_info, {asset_map, pair_id_map, decimals_map} ->
      token_indices = spot_info["tokens"] || []

      if length(token_indices) >= 2 do
        base_token = Map.get(token_by_index, Enum.at(token_indices, 0), %{})
        quote_token = Map.get(token_by_index, Enum.at(token_indices, 1), %{})

        if base_token != %{} and quote_token != %{} do
          base_name = Map.get(base_token, "name", "")
          quote_name = Map.get(quote_token, "name", "")
          # HTTP module transforms szDecimals -> sz_decimals
          base_sz_decimals = Map.get(base_token, "sz_decimals", 8)

          pair_key = "#{base_name}/#{quote_name}"
          asset_id = 10_000 + spot_info["index"]
          pair_id = spot_info["name"]

          {
            Map.put(asset_map, pair_key, asset_id),
            Map.put(pair_id_map, pair_key, pair_id),
            Map.put(decimals_map, pair_key, base_sz_decimals)
          }
        else
          {asset_map, pair_id_map, decimals_map}
        end
      else
        {asset_map, pair_id_map, decimals_map}
      end
    end)
  end

  # ===================== Low-level Cache Operations =====================

  @doc """
  Get a value from the cache by key.
  """
  def get(key) do
    case Cachex.get(@cache, key) do
      {:ok, value} -> value
      {:error, _} -> nil
    end
  end

  @doc """
  Put a key-value pair into the cache.
  """
  def put(key, value) do
    cache_put(key, value)
  end

  @doc """
  Delete a key from the cache.
  """
  def del(key) do
    Cachex.del!(@cache, key)
  end

  @doc """
  Check if a key exists in the cache.
  """
  def exists?(key) do
    case Cachex.exists?(@cache, key) do
      {:ok, exists} -> exists
      _ -> false
    end
  end

  @doc """
  Clear all entries in the cache.
  """
  def clear do
    Cachex.clear!(@cache)
  end
end
