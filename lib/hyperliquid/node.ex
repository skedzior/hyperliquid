defmodule Hyperliquid.Node do
  @moduledoc """
  Client for interacting with a local Hyperliquid node.

  Local nodes can serve EVM JSON-RPC (`/evm`) and Info API (`/info`) endpoints
  when started with `--serve-eth-rpc` and `--serve-info` flags. This gives lower
  latency, no rate limits, and reduced trust assumptions.

  ## Info Endpoints

  Convenience functions are generated for the documented subset of info requests
  supported by the local info server. Each function sends the request to the
  node's `/info` endpoint and parses the response using the corresponding
  endpoint module when available.

      # Documented endpoints with parsed struct responses
      Hyperliquid.Node.meta()
      Hyperliquid.Node.clearinghouse_state("0x...")

      # Generic fallback for any info request (returns raw snake_cased map)
      Hyperliquid.Node.info_request(%{type: "someEndpoint"})

  ## File Snapshots

  The local info server supports `fileSnapshot` requests that write large
  snapshot data to files on the node's filesystem.

      Hyperliquid.Node.file_snapshot(%{type: "referrerStates"}, "/tmp/out.json")
      Hyperliquid.Node.referrer_states_snapshot("/tmp/out.json")
      Hyperliquid.Node.l4_snapshots("/tmp/out.json")

  ## EVM RPC

  When `enable_node_rpc: true` is configured, a `:node` named RPC is registered
  at startup pointing to `node_url/evm`. You can use it directly:

      Hyperliquid.Rpc.Eth.block_number(rpc_name: :node)

  Or through the convenience helpers:

      Hyperliquid.Node.rpc_call("eth_blockNumber")

  ## Configuration

  Info and RPC can be enabled independently:

      config :hyperliquid,
        node_url: "http://localhost:3001",
        enable_node_info: true,  # enables Node info convenience functions
        enable_node_rpc: true    # registers :node named RPC at startup
  """

  alias Hyperliquid.Transport.Http
  alias Hyperliquid.Transport.Rpc

  # Documented supported endpoints on the local info server.
  # Format: {function_name, request_type, endpoint_module, params}
  # params: [] = no params, [:user] = required user param, etc.
  @supported_endpoints [
    {:meta, "meta", Hyperliquid.Api.Info.Meta, []},
    {:spot_meta, "spotMeta", Hyperliquid.Api.Info.SpotMeta, []},
    {:clearinghouse_state, "clearinghouseState", Hyperliquid.Api.Info.ClearinghouseState, [:user]},
    {:spot_clearinghouse_state, "spotClearinghouseState",
     Hyperliquid.Api.Info.SpotClearinghouseState, [:user]},
    {:open_orders, "openOrders", Hyperliquid.Api.Info.OpenOrders, [:user]},
    {:exchange_status, "exchangeStatus", Hyperliquid.Api.Info.ExchangeStatus, []},
    {:frontend_open_orders, "frontendOpenOrders", Hyperliquid.Api.Info.FrontendOpenOrders,
     [:user]},
    {:liquidatable, "liquidatable", Hyperliquid.Api.Info.Liquidatable, []},
    {:active_asset_data, "activeAssetData", Hyperliquid.Api.Info.ActiveAssetData, [:user, :coin]},
    {:max_market_order_ntls, "maxMarketOrderNtls", Hyperliquid.Api.Info.MaxMarketOrderNtls,
     [:user]},
    {:vault_summaries, "vaultSummaries", Hyperliquid.Api.Info.VaultSummaries, []},
    {:user_vault_equities, "userVaultEquities", Hyperliquid.Api.Info.UserVaultEquities, [:user]},
    {:leading_vaults, "leadingVaults", Hyperliquid.Api.Info.LeadingVaults, []},
    {:extra_agents, "extraAgents", Hyperliquid.Api.Info.ExtraAgents, [:user]},
    {:sub_accounts, "subAccounts", Hyperliquid.Api.Info.SubAccounts, [:user]},
    {:user_fees, "userFees", Hyperliquid.Api.Info.UserFees, [:user]},
    {:user_rate_limit, "userRateLimit", Hyperliquid.Api.Info.UserRateLimit, [:user]},
    {:spot_deploy_state, "spotDeployState", Hyperliquid.Api.Info.SpotDeployState, []},
    {:perp_deploy_auction_status, "perpDeployAuctionStatus",
     Hyperliquid.Api.Info.PerpDeployAuctionStatus, []},
    {:delegations, "delegations", Hyperliquid.Api.Info.Delegations, [:user]},
    {:delegator_summary, "delegatorSummary", Hyperliquid.Api.Info.DelegatorSummary, [:user]},
    {:max_builder_fee, "maxBuilderFee", Hyperliquid.Api.Info.MaxBuilderFee, [:user]},
    {:user_to_multi_sig_signers, "userToMultiSigSigners",
     Hyperliquid.Api.Info.UserToMultiSigSigners, [:user]},
    {:user_role, "userRole", Hyperliquid.Api.Info.UserRole, [:user]},
    {:perps_at_open_interest_cap, "perpsAtOpenInterestCap",
     Hyperliquid.Api.Info.PerpsAtOpenInterestCap, []},
    {:validator_l1_votes, "validatorL1Votes", Hyperliquid.Api.Info.ValidatorL1Votes, []},
    {:margin_table, "marginTable", Hyperliquid.Api.Info.MarginTable, []},
    {:perp_dexs, "perpDexs", Hyperliquid.Api.Info.PerpDexs, []},
    # webData2 doesn't compute assetCtxs on node, no dedicated module
    {:web_data2, "webData2", nil, [:user]}
  ]

  # Generate convenience functions from the endpoint list
  for {func_name, request_type, endpoint_mod, params} <- @supported_endpoints do
    case params do
      [] ->
        @doc "Fetch `#{request_type}` from the local node."
        def unquote(func_name)() do
          with {:ok, data} <- Http.node_info_request(%{type: unquote(request_type)}) do
            maybe_parse(unquote(endpoint_mod), data)
          end
        end

      [:user] ->
        @doc "Fetch `#{request_type}` for the given user from the local node."
        def unquote(func_name)(user) do
          with {:ok, data} <-
                 Http.node_info_request(%{type: unquote(request_type), user: user}) do
            maybe_parse(unquote(endpoint_mod), data)
          end
        end

      [:user, :coin] ->
        @doc "Fetch `#{request_type}` for the given user and coin from the local node."
        def unquote(func_name)(user, coin) do
          with {:ok, data} <-
                 Http.node_info_request(%{
                   type: unquote(request_type),
                   user: user,
                   coin: coin
                 }) do
            maybe_parse(unquote(endpoint_mod), data)
          end
        end
    end
  end

  @doc """
  Send any info request to the local node.

  This is a generic fallback that accepts any payload. Use this for
  undocumented endpoints or when you need full control over the request.

  ## Examples

      Hyperliquid.Node.info_request(%{type: "someEndpoint"})
      Hyperliquid.Node.info_request(%{type: "clearinghouseState", user: "0x..."})
  """
  def info_request(payload, opts \\ []) do
    Http.node_info_request(payload, opts)
  end

  # ===================== File Snapshots =====================

  @doc """
  Send a `fileSnapshot` request to the local node.

  File snapshot requests write large data sets to a file on the node's filesystem
  rather than returning them in the HTTP response.

  ## Parameters
    - `request`: The inner request map (e.g., `%{type: "referrerStates"}`)
    - `out_path`: Absolute path on the node where the snapshot file will be written
    - `opts`:
      - `:include_height` - Whether to include block height in output (default: `false`)

  ## Examples

      Hyperliquid.Node.file_snapshot(%{type: "referrerStates"}, "/tmp/out.json")
  """
  def file_snapshot(request, out_path, opts \\ []) do
    payload = %{
      type: "fileSnapshot",
      request: request,
      outPath: out_path,
      includeHeightInOutput: Keyword.get(opts, :include_height, false)
    }

    Http.node_info_request(payload)
  end

  @doc """
  Write a referrer states snapshot to a file on the node.

  ## Parameters
    - `out_path`: File path on the node
    - `opts`: See `file_snapshot/3`
  """
  def referrer_states_snapshot(out_path, opts \\ []),
    do: file_snapshot(%{type: "referrerStates"}, out_path, opts)

  @doc """
  Write L4 snapshots to a file on the node.

  ## Parameters
    - `out_path`: File path on the node
    - `opts`:
      - `:include_users` - Include user data (default: `true`)
      - `:include_trigger_orders` - Include trigger orders (default: `true`)
      - `:include_height` - Include block height in output (default: `false`)
  """
  def l4_snapshots(out_path, opts \\ []) do
    file_snapshot(
      %{
        type: "l4Snapshots",
        includeUsers: Keyword.get(opts, :include_users, true),
        includeTriggerOrders: Keyword.get(opts, :include_trigger_orders, true)
      },
      out_path,
      opts
    )
  end

  # ===================== EVM RPC =====================

  @doc """
  Make a JSON-RPC call to the node's EVM endpoint.

  Requires `enable_node_rpc: true` in config so the `:node` named RPC is registered.

  ## Examples

      Hyperliquid.Node.rpc_call("eth_blockNumber")
      Hyperliquid.Node.rpc_call("eth_getBalance", ["0x...", "latest"])
  """
  def rpc_call(method, params \\ []), do: Rpc.call(method, params, rpc_name: :node)

  @doc """
  Like `rpc_call/2` but raises on error.
  """
  def rpc_call!(method, params \\ []), do: Rpc.call!(method, params, rpc_name: :node)

  # ===================== Health =====================

  @doc """
  Ping the local node by requesting exchange status.

  Returns `{:ok, data}` if the node is reachable, `{:error, reason}` otherwise.
  """
  def ping, do: Http.node_info_request(%{type: "exchangeStatus"})

  # ===================== Private =====================

  defp maybe_parse(nil, data), do: {:ok, data}

  defp maybe_parse(mod, data) do
    Code.ensure_loaded!(mod)
    data = if function_exported?(mod, :preprocess, 1), do: mod.preprocess(data), else: data
    mod.parse_response(data)
  end
end
