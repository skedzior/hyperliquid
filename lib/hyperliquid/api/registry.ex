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

  # Discover all endpoint modules by scanning the application
  # This automatically finds all modules that use the Endpoint DSL
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
      Hyperliquid.Api.Info.PredictedFundings,
      Hyperliquid.Api.Info.PreTransferCheck,
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
      Hyperliquid.Api.Exchange.Noop,
      Hyperliquid.Api.Exchange.SetDisplayName
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
    |> Enum.filter(&function_exported?(&1, :__endpoint_info__, 0))
    |> Enum.map(& &1.__endpoint_info__())
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

  - `type` - `:info`, `:exchange`, or `:subscription`

  ## Returns

  List of endpoint info maps of the specified type.
  """
  def list_by_type(type) when type in [:info, :exchange, :subscription] do
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

  Searches all contexts for the endpoint.

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

  - `context` - Atom: `:info`, `:exchange`, `:explorer`, or `:stats`

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
