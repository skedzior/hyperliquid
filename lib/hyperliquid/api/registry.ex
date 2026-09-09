defmodule Hyperliquid.Api.Registry do
  @moduledoc """
  Registry for discovering and introspecting API endpoints.

  This module provides functions to list all available endpoints and
  get their documentation, rate limits, and other metadata.

  ## Usage

      # List all endpoints
      Hyperliquid.Api.Registry.list_endpoints()

      # Get info for a specific endpoint
      Hyperliquid.Api.Registry.get_endpoint_info("allMids")

      # List endpoints by type
      Hyperliquid.Api.Registry.list_by_type(:info)

      # Get total rate limit cost for multiple endpoints
      Hyperliquid.Api.Registry.total_rate_limit_cost(["allMids", "l2Book"])
  """

  # Every endpoint module in the library, grouped by context.
  #
  # This list is exhaustive and is asserted against the filesystem by
  # `test/api/registry_coverage_test.exs` — every module under
  # `lib/hyperliquid/api/{info,exchange,subscription,explorer,stats}/` must
  # appear here (with the single documented exception of
  # `Hyperliquid.Api.Exchange.KeyUtils`, a helper rather than an endpoint).
  #
  # Note that not every registered module carries metadata:
  #
  #   * `info`/`explorer`/`stats` modules use the `Endpoint` DSL and export
  #     `__endpoint_info__/0`
  #   * `subscription` modules use the `SubscriptionEndpoint` DSL and export
  #     `__subscription_info__/0`
  #   * most `exchange` modules are hand-written action builders with neither;
  #     they are registered so `resolve_endpoint/2` and
  #     `list_context_endpoints/1` see them, but they do not appear in
  #     `list_endpoints/0`.
  #
  # `Hyperliquid.Api.MultiSig` is deliberately absent: it wraps other actions
  # rather than being an endpoint of its own.
  @endpoints_by_context %{
    info: [
      Hyperliquid.Api.Info.ActiveAssetData,
      Hyperliquid.Api.Info.AlignedQuoteTokenInfo,
      Hyperliquid.Api.Info.AllBorrowLendReserveStates,
      Hyperliquid.Api.Info.AllMids,
      Hyperliquid.Api.Info.AllPerpMetas,
      Hyperliquid.Api.Info.ApprovedBuilders,
      Hyperliquid.Api.Info.BorrowLendReserveState,
      Hyperliquid.Api.Info.BorrowLendUserState,
      Hyperliquid.Api.Info.CandleSnapshot,
      Hyperliquid.Api.Info.ClearinghouseState,
      Hyperliquid.Api.Info.Delegations,
      Hyperliquid.Api.Info.DelegatorHistory,
      Hyperliquid.Api.Info.DelegatorRewards,
      Hyperliquid.Api.Info.DelegatorSummary,
      Hyperliquid.Api.Info.ExchangeStatus,
      Hyperliquid.Api.Info.ExtraAgents,
      Hyperliquid.Api.Info.FrontendOpenOrders,
      Hyperliquid.Api.Info.FundingHistory,
      Hyperliquid.Api.Info.GossipPriorityAuctionStatus,
      Hyperliquid.Api.Info.GossipRootIps,
      Hyperliquid.Api.Info.HistoricalOrders,
      Hyperliquid.Api.Info.IsVip,
      Hyperliquid.Api.Info.L2Book,
      Hyperliquid.Api.Info.LeadingVaults,
      Hyperliquid.Api.Info.LegalCheck,
      Hyperliquid.Api.Info.Liquidatable,
      Hyperliquid.Api.Info.MarginTable,
      Hyperliquid.Api.Info.MaxBuilderFee,
      Hyperliquid.Api.Info.MaxMarketOrderNtls,
      Hyperliquid.Api.Info.Meta,
      Hyperliquid.Api.Info.MetaAndAssetCtxs,
      Hyperliquid.Api.Info.OpenOrders,
      Hyperliquid.Api.Info.OrderStatus,
      Hyperliquid.Api.Info.OutcomeDeployerLimits,
      Hyperliquid.Api.Info.OutcomeMeta,
      Hyperliquid.Api.Info.OutcomeTemplates,
      Hyperliquid.Api.Info.PerpAnnotation,
      Hyperliquid.Api.Info.PerpCategories,
      Hyperliquid.Api.Info.PerpConciseAnnotations,
      Hyperliquid.Api.Info.PerpDeployAuctionStatus,
      Hyperliquid.Api.Info.PerpDexLimits,
      Hyperliquid.Api.Info.PerpDexStatus,
      Hyperliquid.Api.Info.PerpDexs,
      Hyperliquid.Api.Info.PerpsAtOpenInterestCap,
      Hyperliquid.Api.Info.Portfolio,
      Hyperliquid.Api.Info.PreTransferCheck,
      Hyperliquid.Api.Info.PredictedFundings,
      Hyperliquid.Api.Info.RecentTrades,
      Hyperliquid.Api.Info.Referral,
      Hyperliquid.Api.Info.SettledOutcome,
      Hyperliquid.Api.Info.SpotClearinghouseState,
      Hyperliquid.Api.Info.SpotDeployState,
      Hyperliquid.Api.Info.SpotMeta,
      Hyperliquid.Api.Info.SpotMetaAndAssetCtxs,
      Hyperliquid.Api.Info.SpotPairDeployAuctionStatus,
      Hyperliquid.Api.Info.SubAccounts,
      Hyperliquid.Api.Info.SubAccounts2,
      Hyperliquid.Api.Info.TokenDetails,
      Hyperliquid.Api.Info.TwapHistory,
      Hyperliquid.Api.Info.UsdcRouting,
      Hyperliquid.Api.Info.UserAbstraction,
      Hyperliquid.Api.Info.UserBorrowLendInterest,
      Hyperliquid.Api.Info.UserDexAbstraction,
      Hyperliquid.Api.Info.UserFees,
      Hyperliquid.Api.Info.UserFills,
      Hyperliquid.Api.Info.UserFillsByTime,
      Hyperliquid.Api.Info.UserFunding,
      Hyperliquid.Api.Info.UserNonFundingLedgerUpdates,
      Hyperliquid.Api.Info.UserRateLimit,
      Hyperliquid.Api.Info.UserRole,
      Hyperliquid.Api.Info.UserToMultiSigSigners,
      Hyperliquid.Api.Info.UserTwapSliceFills,
      Hyperliquid.Api.Info.UserTwapSliceFillsByTime,
      Hyperliquid.Api.Info.UserVaultEquities,
      Hyperliquid.Api.Info.ValidatorL1Votes,
      Hyperliquid.Api.Info.ValidatorSummaries,
      Hyperliquid.Api.Info.VaultDetails,
      Hyperliquid.Api.Info.VaultSummaries,
      Hyperliquid.Api.Info.WebData2
    ],
    exchange: [
      Hyperliquid.Api.Exchange.ActivateOutcomeDeployer,
      Hyperliquid.Api.Exchange.AgentEnableDexAbstraction,
      Hyperliquid.Api.Exchange.AgentSendAsset,
      Hyperliquid.Api.Exchange.AgentSetAbstraction,
      Hyperliquid.Api.Exchange.ApproveAgent,
      Hyperliquid.Api.Exchange.ApproveBuilderFee,
      Hyperliquid.Api.Exchange.AuthorizeAqav2Role,
      Hyperliquid.Api.Exchange.BatchModify,
      Hyperliquid.Api.Exchange.BorrowLend,
      Hyperliquid.Api.Exchange.CDeposit,
      Hyperliquid.Api.Exchange.CSignerAction,
      Hyperliquid.Api.Exchange.CValidatorAction,
      Hyperliquid.Api.Exchange.CWithdraw,
      Hyperliquid.Api.Exchange.Cancel,
      Hyperliquid.Api.Exchange.CancelByCloid,
      Hyperliquid.Api.Exchange.ClaimRewards,
      Hyperliquid.Api.Exchange.ConvertToMultiSigUser,
      Hyperliquid.Api.Exchange.CreateSubAccount,
      Hyperliquid.Api.Exchange.CreateVault,
      Hyperliquid.Api.Exchange.EvmUserModify,
      Hyperliquid.Api.Exchange.FinalizeEvmContract,
      Hyperliquid.Api.Exchange.GossipPriorityBid,
      Hyperliquid.Api.Exchange.Hip3LiquidatorTransfer,
      Hyperliquid.Api.Exchange.LinkStakingUser,
      Hyperliquid.Api.Exchange.Modify,
      Hyperliquid.Api.Exchange.Noop,
      Hyperliquid.Api.Exchange.Order,
      Hyperliquid.Api.Exchange.OutcomeDeploy,
      Hyperliquid.Api.Exchange.PerpDeploy,
      Hyperliquid.Api.Exchange.RegisterReferrer,
      Hyperliquid.Api.Exchange.ReserveRequestWeight,
      Hyperliquid.Api.Exchange.ScheduleCancel,
      Hyperliquid.Api.Exchange.SendAsset,
      Hyperliquid.Api.Exchange.SendToEvmWithData,
      Hyperliquid.Api.Exchange.SetDisplayName,
      Hyperliquid.Api.Exchange.SetReferrer,
      Hyperliquid.Api.Exchange.SpotDeploy,
      Hyperliquid.Api.Exchange.SpotSend,
      Hyperliquid.Api.Exchange.SpotUser,
      Hyperliquid.Api.Exchange.StakingLinkDisableTradingUser,
      Hyperliquid.Api.Exchange.SubAccountModify,
      Hyperliquid.Api.Exchange.SubAccountSpotTransfer,
      Hyperliquid.Api.Exchange.SubAccountTransfer,
      Hyperliquid.Api.Exchange.TokenDelegate,
      Hyperliquid.Api.Exchange.TopUpIsolatedOnlyMargin,
      Hyperliquid.Api.Exchange.TwapCancel,
      Hyperliquid.Api.Exchange.TwapOrder,
      Hyperliquid.Api.Exchange.UpdateIsolatedMargin,
      Hyperliquid.Api.Exchange.UpdateLeverage,
      Hyperliquid.Api.Exchange.UsdClassTransfer,
      Hyperliquid.Api.Exchange.UsdSend,
      Hyperliquid.Api.Exchange.UserDexAbstraction,
      Hyperliquid.Api.Exchange.UserOutcome,
      Hyperliquid.Api.Exchange.UserPortfolioMargin,
      Hyperliquid.Api.Exchange.UserSetAbstraction,
      Hyperliquid.Api.Exchange.ValidatorL1Stream,
      Hyperliquid.Api.Exchange.VaultDistribute,
      Hyperliquid.Api.Exchange.VaultModify,
      Hyperliquid.Api.Exchange.VaultTransfer,
      Hyperliquid.Api.Exchange.Withdraw3
    ],
    subscription: [
      Hyperliquid.Api.Subscription.ActiveAssetCtx,
      Hyperliquid.Api.Subscription.ActiveAssetData,
      Hyperliquid.Api.Subscription.ActiveSpotAssetCtx,
      Hyperliquid.Api.Subscription.AllDexsAssetCtxs,
      Hyperliquid.Api.Subscription.AllDexsClearinghouseState,
      Hyperliquid.Api.Subscription.AllMids,
      Hyperliquid.Api.Subscription.AssetCtxs,
      Hyperliquid.Api.Subscription.Bbo,
      Hyperliquid.Api.Subscription.Candle,
      Hyperliquid.Api.Subscription.ClearinghouseState,
      Hyperliquid.Api.Subscription.ExplorerBlock,
      Hyperliquid.Api.Subscription.ExplorerTxs,
      Hyperliquid.Api.Subscription.FastAssetCtxs,
      Hyperliquid.Api.Subscription.L2Book,
      Hyperliquid.Api.Subscription.Notification,
      Hyperliquid.Api.Subscription.OpenOrders,
      Hyperliquid.Api.Subscription.OrderUpdates,
      Hyperliquid.Api.Subscription.OutcomeMetaUpdates,
      Hyperliquid.Api.Subscription.SpotAssetCtxs,
      Hyperliquid.Api.Subscription.SpotState,
      Hyperliquid.Api.Subscription.Trades,
      Hyperliquid.Api.Subscription.TwapStates,
      Hyperliquid.Api.Subscription.UserEvents,
      Hyperliquid.Api.Subscription.UserFills,
      Hyperliquid.Api.Subscription.UserFundings,
      Hyperliquid.Api.Subscription.UserHistoricalOrders,
      Hyperliquid.Api.Subscription.UserNonFundingLedgerUpdates,
      Hyperliquid.Api.Subscription.UserTwapHistory,
      Hyperliquid.Api.Subscription.UserTwapSliceFills,
      Hyperliquid.Api.Subscription.WebData2,
      Hyperliquid.Api.Subscription.WebData3
    ],
    explorer: [
      Hyperliquid.Api.Explorer.BlockDetails,
      Hyperliquid.Api.Explorer.TxDetails,
      Hyperliquid.Api.Explorer.UserDetails
    ],
    stats: [
      Hyperliquid.Api.Stats.Leaderboard,
      Hyperliquid.Api.Stats.Vaults
    ]
  }

  # Flatten all endpoints for backwards compatibility
  @endpoints @endpoints_by_context
             |> Map.values()
             |> List.flatten()

  @doc """
  List all registered endpoints with their metadata.

  ## Returns

  List of endpoint info maps.

  ## Example

      iex> Hyperliquid.Api.Registry.list_endpoints()
      [
        %{endpoint: "allMids", type: :info, rate_limit_cost: 2, ...},
        %{endpoint: "l2Book", type: :info, rate_limit_cost: 2, ...}
      ]
  """
  def list_endpoints do
    @endpoints
    |> Enum.map(fn mod ->
      Code.ensure_loaded!(mod)
      mod
    end)
    |> Enum.flat_map(fn mod ->
      cond do
        function_exported?(mod, :__endpoint_info__, 0) ->
          [mod.__endpoint_info__()]

        # Subscription modules use the `SubscriptionEndpoint` DSL, which exports
        # `__subscription_info__/0` instead of `__endpoint_info__/0`. Normalise
        # it into the same shape so `list_by_type(:subscription)` works.
        function_exported?(mod, :__subscription_info__, 0) ->
          [subscription_info_to_endpoint_info(mod.__subscription_info__())]

        # Exchange action modules that have not been migrated to the
        # `ExchangeEndpoint` DSL expose no metadata at all — they are still
        # registered (so `resolve_endpoint/2` finds them) but cannot be listed.
        true ->
          []
      end
    end)
  end

  # Normalise `__subscription_info__/0` into the `__endpoint_info__/0` shape.
  defp subscription_info_to_endpoint_info(info) do
    %{
      endpoint: info.request_type,
      type: :subscription,
      rate_limit_cost: 0,
      params: info.params,
      optional_params: info.optional_params,
      doc: info.doc,
      returns: "",
      module: info.module,
      connection_type: info.connection_type
    }
  end

  @doc """
  Get endpoint info by endpoint name.

  ## Parameters

  - `name` - The endpoint name (e.g., "allMids", "l2Book")

  ## Returns

  - `{:ok, info}` - Endpoint info map
  - `{:error, :not_found}` - Endpoint not found
  """
  def get_endpoint_info(name) when is_binary(name) do
    case Enum.find(list_endpoints(), &(&1.endpoint == name)) do
      nil -> {:error, :not_found}
      info -> {:ok, info}
    end
  end

  @doc """
  List endpoints by type.

  ## Parameters

  - `type` - `:info`, `:exchange`, `:subscription`, `:explorer` or `:stats`

  ## Returns

  List of endpoint info maps of the specified type.

  Note that `:exchange` only returns the modules that use the
  `Hyperliquid.Api.ExchangeEndpoint` DSL; the remaining hand-written action
  modules carry no metadata. Use `list_context_endpoints(:exchange)` for the
  full module list.
  """
  def list_by_type(type) when type in [:info, :exchange, :subscription, :explorer, :stats] do
    list_endpoints()
    |> Enum.filter(&(&1.type == type))
  end

  @doc """
  Calculate total rate limit cost for a list of endpoints.

  ## Parameters

  - `names` - List of endpoint names

  ## Returns

  Total rate limit cost as integer.

  ## Example

      iex> Hyperliquid.Api.Registry.total_rate_limit_cost(["allMids", "l2Book"])
      4
  """
  def total_rate_limit_cost(names) when is_list(names) do
    names
    |> Enum.map(&get_endpoint_info/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, info} -> info.rate_limit_cost end)
    |> Enum.sum()
  end

  @doc """
  Get endpoint documentation as formatted string.

  ## Parameters

  - `name` - The endpoint name

  ## Returns

  Formatted documentation string or error.
  """
  def docs(name) when is_binary(name) do
    case get_endpoint_info(name) do
      {:ok, info} ->
        """
        Endpoint: #{info.endpoint}
        Type: #{info.type}
        Rate Limit Cost: #{info.rate_limit_cost} (out of 1200/min)

        Description:
        #{if info.doc != "", do: info.doc, else: "No description available"}

        Returns:
        #{if info.returns != "", do: info.returns, else: "No return info available"}

        Parameters:
        #{format_params(info.params, info.optional_params)}

        Module: #{inspect(info.module)}
        """

      {:error, :not_found} ->
        {:error, "Endpoint '#{name}' not found"}
    end
  end

  defp format_params([], []), do: "None"

  defp format_params(required, optional) do
    required_str =
      if required != [] do
        "Required: #{Enum.join(required, ", ")}"
      else
        ""
      end

    optional_str =
      if optional != [] do
        "Optional: #{Enum.join(optional, ", ")}"
      else
        ""
      end

    [required_str, optional_str]
    |> Enum.filter(&(&1 != ""))
    |> Enum.join("\n")
  end

  @doc """
  Print formatted documentation for an endpoint.

  ## Parameters

  - `name` - The endpoint name
  """
  def print_docs(name) do
    case docs(name) do
      {:error, msg} -> IO.puts(msg)
      doc -> IO.puts(doc)
    end
  end

  @doc """
  Returns a summary of rate limits for all endpoints.

  Groups endpoints by their rate limit cost.
  """
  def rate_limit_summary do
    list_endpoints()
    |> Enum.group_by(& &1.rate_limit_cost)
    |> Enum.sort_by(fn {cost, _} -> cost end)
    |> Enum.map(fn {cost, endpoints} ->
      names = Enum.map(endpoints, & &1.endpoint)
      {cost, names}
    end)
  end

  @doc """
  Resolve an endpoint module from context and endpoint name.

  Converts the endpoint name from snake_case to the corresponding module name.

  ## Parameters

  - `context` - Atom: `:info`, `:exchange`, `:explorer`, or `:stats`
  - `endpoint_name` - Atom in snake_case (e.g., `:all_mids`, `:l2_book`)

  ## Returns

  - `{:ok, module}` - The endpoint module
  - `{:error, :not_found}` - Endpoint not found

  ## Examples

      iex> Hyperliquid.Api.Registry.resolve_endpoint(:info, :all_mids)
      {:ok, Hyperliquid.Api.Info.AllMids}

      iex> Hyperliquid.Api.Registry.resolve_endpoint(:info, :l2_book)
      {:ok, Hyperliquid.Api.Info.L2Book}

      iex> Hyperliquid.Api.Registry.resolve_endpoint(:info, :nonexistent)
      {:error, :not_found}
  """
  def resolve_endpoint(context, endpoint_name) when is_atom(context) and is_atom(endpoint_name) do
    module_name = snake_to_module_name(endpoint_name)

    context_module =
      case context do
        :info -> Hyperliquid.Api.Info
        :exchange -> Hyperliquid.Api.Exchange
        :subscription -> Hyperliquid.Api.Subscription
        :explorer -> Hyperliquid.Api.Explorer
        :stats -> Hyperliquid.Api.Stats
        _ -> nil
      end

    if context_module do
      full_module = Module.concat(context_module, module_name)

      # Check if module exists in our registry
      endpoints = Map.get(@endpoints_by_context, context, [])

      if full_module in endpoints do
        {:ok, full_module}
      else
        {:error, :not_found}
      end
    else
      {:error, {:invalid_context, context}}
    end
  end

  @doc """
  Get endpoint module by snake_case name without context.

  Searches all contexts for the endpoint. Several names exist in more than one
  context (`all_mids`, `l2_book`, `user_fills`, `user_dex_abstraction`, ...),
  in which case `{:error, {:ambiguous, modules}}` is returned — use
  `resolve_endpoint/2` with an explicit context for those.

  ## Parameters

  - `endpoint_name` - Atom in snake_case

  ## Returns

  - `{:ok, module}` - The endpoint module
  - `{:error, :not_found}` - Endpoint not found
  - `{:error, {:ambiguous, modules}}` - Multiple endpoints with same name
  """
  def get_endpoint_module(endpoint_name) when is_atom(endpoint_name) do
    module_name = snake_to_module_name(endpoint_name)

    matches =
      @endpoints_by_context
      |> Enum.flat_map(fn {_context, modules} -> modules end)
      |> Enum.filter(fn mod ->
        mod
        |> Module.split()
        |> List.last()
        |> Kernel.==(module_name)
      end)

    case matches do
      [] -> {:error, :not_found}
      [module] -> {:ok, module}
      modules -> {:error, {:ambiguous, modules}}
    end
  end

  @doc """
  List all endpoints for a specific context.

  ## Parameters

  - `context` - Atom: `:info`, `:exchange`, `:subscription`, `:explorer`, or `:stats`

  ## Returns

  List of endpoint modules for the context.
  """
  def list_context_endpoints(context) when is_atom(context) do
    Map.get(@endpoints_by_context, context, [])
  end

  # Convert snake_case atom to PascalCase module name string
  # Examples:
  #   :all_mids -> "AllMids"
  #   :l2_book -> "L2Book"
  #   :clearinghouse_state -> "ClearinghouseState"
  defp snake_to_module_name(snake_atom) when is_atom(snake_atom) do
    snake_atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end
end
