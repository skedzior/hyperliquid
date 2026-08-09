defmodule Hyperliquid.Transport.Http do
  @moduledoc """
  HTTP transport layer for Hyperliquid API.

  Provides low-level HTTP communication with the Hyperliquid Info and Exchange APIs.
  Uses HTTPoison for HTTP requests with automatic JSON encoding/decoding and
  camelCase to snake_case transformation.

  ## Usage

      # Info API request (no auth needed)
      {:ok, response} = Http.info_request(%{type: "allMids"})

      # Exchange API request (requires signature)
      {:ok, response} = Http.exchange_request(action, signature, nonce)

      # Raw POST request
      {:ok, response} = Http.post("/info", %{type: "meta"})

  ## Configuration

  The HTTP transport uses `Hyperliquid.Config` for URL configuration:
  - `Config.api_base/0` - Base URL for API requests
  - `Config.mainnet?/0` - Whether to use mainnet or testnet
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Error

  @default_timeout 30_000
  @default_recv_timeout 30_000
  @json_content_type "application/json"

  @type request_opts :: [
          timeout: non_neg_integer(),
          recv_timeout: non_neg_integer(),
          raw: boolean()
        ]

  @type response :: {:ok, map() | list()} | {:error, Error.t()}

  # ===================== Public API =====================

  @doc """
  Make a request to the Info API.

  The Info API is used for read-only queries and doesn't require authentication.

  ## Parameters
    - `payload`: Map with query parameters (must include `"type"` key)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, response}` - Parsed JSON response (snake_cased)
    - `{:error, %Error{}}` - Error with details

  ## Examples

      # Get all mid prices
      {:ok, mids} = Http.info_request(%{type: "allMids"})

      # Get user state
      {:ok, state} = Http.info_request(%{type: "clearinghouseState", user: "0x..."})

      # Get meta information
      {:ok, meta} = Http.info_request(%{type: "meta"})
  """
  @spec info_request(map(), request_opts()) :: response()
  def info_request(payload, opts \\ []) when is_map(payload) do
    url = "#{Config.api_base()}/info"
    post(url, payload, opts)
  end

  @doc """
  Make a request to the Explorer API.

  Used for block_details, user_details, and tx_details endpoints.

  ## Parameters
    - `payload`: Map with request type and parameters
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, response}` - Parsed JSON response (snake_cased)
    - `{:error, %Error{}}` - Error with details

  ## Examples

      # Get block details
      {:ok, block} = Http.explorer_request(%{type: "blockDetails", height: 12345})

      # Get transaction details
      {:ok, tx} = Http.explorer_request(%{type: "txDetails", hash: "0x..."})
  """
  @spec explorer_request(map(), request_opts()) :: response()
  def explorer_request(payload, opts \\ []) when is_map(payload) do
    url = Config.explorer_url()
    post(url, payload, opts)
  end

  @doc """
  Make a request to the Stats API.

  Used for leaderboard, vaults, and other stats endpoints.
  Stats endpoints use GET requests to a network-specific URL.

  ## Parameters
    - `endpoint`: The endpoint name (e.g., "leaderboard", "vaults")
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, response}` - Parsed JSON response (snake_cased)
    - `{:error, %Error{}}` - Error with details

  ## Examples

      # Get leaderboard
      {:ok, leaderboard} = Http.stats_request("leaderboard")

      # Get vaults
      {:ok, vaults} = Http.stats_request("vaults")
  """
  @spec stats_request(String.t(), request_opts()) :: response()
  def stats_request(endpoint, opts \\ []) when is_binary(endpoint) do
    network = if Config.mainnet?(), do: "Mainnet", else: "Testnet"
    url = "#{Config.stats_base()}/#{network}/#{endpoint}"
    get(url, opts)
  end

  @doc """
  Make a request to the Exchange API.

  The Exchange API is used for trading operations and requires EIP-712 signatures.

  ## Parameters
    - `action`: The action map (order, cancel, etc.)
    - `signature`: EIP-712 signature
    - `nonce`: Timestamp nonce
    - `vault_address`: Optional vault address
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, response}` - Parsed JSON response (snake_cased)
    - `{:error, %Error{}}` - Error with details

  ## Examples

      {:ok, result} = Http.exchange_request(
        %{type: "order", orders: [...], grouping: "na"},
        signature,
        nonce
      )
  """
  @spec exchange_request(
          map(),
          map(),
          non_neg_integer(),
          String.t() | nil,
          non_neg_integer() | nil,
          request_opts()
        ) ::
          response()
  def exchange_request(
        action,
        signature,
        nonce,
        vault_address \\ nil,
        expires_after \\ nil,
        opts \\ []
      ) do
    url = "#{Config.api_base()}/exchange"

    # The signed preimage is the msgpack of the action, so the body must carry
    # the same field order that was hashed. canonicalize/1 is idempotent, so it
    # is safe for callers that already canonicalized before signing.
    payload = %{
      action: Hyperliquid.Api.ActionEncoder.canonicalize(action),
      nonce: nonce,
      signature: signature,
      expiresAfter: expires_after
    }

    payload =
      if vault_address do
        Map.put(payload, :vaultAddress, vault_address)
      else
        payload
      end

    post(url, payload, opts)
  end

  @doc """
  Make a user-signed (EIP-712) exchange request.

  Used for actions like usdSend, withdraw3, spotSend that use typed data signatures.

  ## Parameters
    - `action`: The action payload
    - `signature`: Signature map with r, s, v
    - `nonce`: Request nonce (timestamp)
    - `opts`: Request options

  ## Returns
    - `{:ok, response}` - Parsed response
    - `{:error, %Error{}}` - Error with details
  """
  @spec user_signed_request(map(), map(), non_neg_integer(), request_opts()) :: response()
  def user_signed_request(action, signature, nonce, opts \\ []) do
    url = "#{Config.api_base()}/exchange"

    payload = %{
      action: action,
      nonce: nonce,
      signature: signature,
      expiresAfter: nil,
      vaultAddress: nil
    }

    post(url, payload, opts)
  end

  @doc """
  Make a raw POST request to any endpoint.

  ## Parameters
    - `url`: Full URL or path (will be appended to api_base if relative)
    - `body`: Request body (will be JSON encoded)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, response}` - Parsed JSON response (snake_cased)
    - `{:error, %Error{}}` - Error with details

  ## Examples

      {:ok, data} = Http.post("/info", %{type: "allMids"})
      {:ok, data} = Http.post("https://api.hyperliquid.xyz/info", %{type: "meta"})
  """
  @spec post(String.t(), map(), request_opts()) :: response()
  def post(url, body, opts \\ []) when is_map(body) do
    full_url = build_url(url)
    json_body = Jason.encode!(body)
    headers = [{"Content-Type", @json_content_type}]
    raw? = Keyword.get(opts, :raw, false)

    http_opts = [
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      recv_timeout: Keyword.get(opts, :recv_timeout, @default_recv_timeout)
    ]

    case HTTPoison.post(full_url, json_body, headers, http_opts) do
      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} when code in 200..299 ->
        parse_response(resp_body, raw?)

      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
        {:error, Error.exception(%{status_code: code, message: resp_body})}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, Error.exception(%{reason: reason})}
    end
  end

  @doc """
  Make a GET request.

  ## Parameters
    - `url`: Full URL or path (will be appended to api_base if relative)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, response}` - Parsed JSON response (snake_cased)
    - `{:error, %Error{}}` - Error with details
  """
  @spec get(String.t(), request_opts()) :: response()
  def get(url, opts \\ []) do
    full_url = build_url(url)

    http_opts = [
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      recv_timeout: Keyword.get(opts, :recv_timeout, @default_recv_timeout)
    ]

    raw? = Keyword.get(opts, :raw, false)

    case HTTPoison.get(full_url, [], http_opts) do
      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} when code in 200..299 ->
        parse_response(resp_body, raw?)

      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
        {:error, Error.exception(%{status_code: code, message: resp_body})}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, Error.exception(%{reason: reason})}
    end
  end

  # ===================== Convenience Functions =====================

  @doc """
  Fetch all mid prices.

  ## Returns
    - `{:ok, %{"BTC" => "43250.5", ...}}` - Map of coin to mid price
    - `{:error, %Error{}}` - Error with details

  ## Example

      {:ok, mids} = Http.all_mids()
      mids["BTC"]
      # => "43250.5"
  """
  @spec all_mids(request_opts()) :: response()
  def all_mids(opts \\ []) do
    info_request(%{type: "allMids"}, opts)
  end

  @doc """
  Fetch perpetuals metadata.

  ## Returns
    - `{:ok, meta}` - Perpetuals metadata
    - `{:error, %Error{}}` - Error with details
  """
  @spec meta(request_opts()) :: response()
  def meta(opts \\ []) do
    info_request(%{type: "meta"}, opts)
  end

  @doc """
  Fetch spot metadata.

  ## Returns
    - `{:ok, meta}` - Spot metadata
    - `{:error, %Error{}}` - Error with details
  """
  @spec spot_meta(request_opts()) :: response()
  def spot_meta(opts \\ []) do
    info_request(%{type: "spotMeta"}, opts)
  end

  @doc """
  Fetch perpetuals metadata with asset contexts.

  ## Returns
    - `{:ok, [meta, asset_ctxs]}` - Meta and asset contexts
    - `{:error, %Error{}}` - Error with details
  """
  @spec meta_and_asset_ctxs(request_opts()) :: response()
  def meta_and_asset_ctxs(opts \\ []) do
    payload =
      case Keyword.get(opts, :dex) do
        nil -> %{type: "metaAndAssetCtxs"}
        dex -> %{type: "metaAndAssetCtxs", dex: dex}
      end

    info_request(payload, opts)
  end

  @doc """
  Fetch spot metadata with asset contexts.

  ## Returns
    - `{:ok, [meta, asset_ctxs]}` - Spot meta and asset contexts
    - `{:error, %Error{}}` - Error with details
  """
  @spec spot_meta_and_asset_ctxs(request_opts()) :: response()
  def spot_meta_and_asset_ctxs(opts \\ []) do
    info_request(%{type: "spotMetaAndAssetCtxs"}, opts)
  end

  @doc """
  Fetch user's perpetuals clearinghouse state.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, state}` - Clearinghouse state with positions
    - `{:error, %Error{}}` - Error with details
  """
  @spec clearinghouse_state(String.t(), request_opts()) :: response()
  def clearinghouse_state(user, opts \\ []) do
    info_request(%{type: "clearinghouseState", user: user}, opts)
  end

  @doc """
  Fetch user's spot clearinghouse state.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, state}` - Spot clearinghouse state with balances
    - `{:error, %Error{}}` - Error with details
  """
  @spec spot_clearinghouse_state(String.t(), request_opts()) :: response()
  def spot_clearinghouse_state(user, opts \\ []) do
    info_request(%{type: "spotClearinghouseState", user: user}, opts)
  end

  @doc """
  Fetch user's open orders.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, orders}` - List of open orders
    - `{:error, %Error{}}` - Error with details
  """
  @spec open_orders(String.t(), request_opts()) :: response()
  def open_orders(user, opts \\ []) do
    info_request(%{type: "openOrders", user: user}, opts)
  end

  @doc """
  Fetch user's order history.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, orders}` - List of historical orders
    - `{:error, %Error{}}` - Error with details
  """
  @spec user_fills(String.t(), request_opts()) :: response()
  def user_fills(user, opts \\ []) do
    info_request(%{type: "userFills", user: user}, opts)
  end

  @doc """
  Fetch funding history for a user.

  ## Parameters
    - `user`: User address (0x...)
    - `start_time`: Start timestamp in ms
    - `end_time`: Optional end timestamp in ms
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, funding}` - Funding history
    - `{:error, %Error{}}` - Error with details
  """
  @spec funding_history(String.t(), non_neg_integer(), non_neg_integer() | nil, request_opts()) ::
          response()
  def funding_history(user, start_time, end_time \\ nil, opts \\ []) do
    payload = %{type: "userFunding", user: user, startTime: start_time}
    payload = if end_time, do: Map.put(payload, :endTime, end_time), else: payload
    info_request(payload, opts)
  end

  @doc """
  Fetch L2 order book snapshot.

  ## Parameters
    - `coin`: Coin symbol (e.g., "BTC")
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, book}` - Order book with levels
    - `{:error, %Error{}}` - Error with details
  """
  @spec l2_book(String.t(), request_opts()) :: response()
  def l2_book(coin, opts \\ []) do
    info_request(%{type: "l2Book", coin: coin}, opts)
  end

  @doc """
  Fetch recent trades for a coin.

  ## Parameters
    - `coin`: Coin symbol (e.g., "BTC")
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, trades}` - List of recent trades
    - `{:error, %Error{}}` - Error with details
  """
  @spec recent_trades(String.t(), request_opts()) :: response()
  def recent_trades(coin, opts \\ []) do
    info_request(%{type: "recentTrades", coin: coin}, opts)
  end

  @doc """
  Fetch candle data.

  ## Parameters
    - `coin`: Coin symbol
    - `interval`: Candle interval (e.g., "1m", "1h", "1d")
    - `start_time`: Start timestamp in ms
    - `end_time`: End timestamp in ms
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, candles}` - List of candle data
    - `{:error, %Error{}}` - Error with details
  """
  @spec candles(String.t(), String.t(), non_neg_integer(), non_neg_integer(), request_opts()) ::
          response()
  def candles(coin, interval, start_time, end_time, opts \\ []) do
    info_request(
      %{
        type: "candleSnapshot",
        req: %{
          coin: coin,
          interval: interval,
          startTime: start_time,
          endTime: end_time
        }
      },
      opts
    )
  end

  @doc """
  Fetch all perpetual DEXs.

  ## Returns
    - `{:ok, dexs}` - List of perpetual DEXs
    - `{:error, %Error{}}` - Error with details
  """
  @spec perp_dexs(request_opts()) :: response()
  def perp_dexs(opts \\ []) do
    info_request(%{type: "perpDexs"}, opts)
  end

  @doc """
  Fetch HIP-4 prediction market outcome metadata.

  Outcome assets are not present in `spotMeta`, so this is the only source for
  resolving `#<encoding>` coins to asset IDs.
  """
  @spec outcome_meta(request_opts()) :: response()
  def outcome_meta(opts \\ []) do
    info_request(%{type: "outcomeMeta"}, opts)
  end

  @doc """
  Fetch limits for a specific perpetual DEX.

  ## Parameters
    - `dex`: DEX name
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, limits}` - DEX limits
    - `{:error, %Error{}}` - Error with details
  """
  @spec perp_dex_limits(String.t(), request_opts()) :: response()
  def perp_dex_limits(dex, opts \\ []) do
    info_request(%{type: "perpDexLimits", dex: dex}, opts)
  end

  @doc """
  Fetch perpetual deploy auction status.

  ## Returns
    - `{:ok, status}` - Auction status
    - `{:error, %Error{}}` - Error with details
  """
  @spec perp_deploy_auction_status(request_opts()) :: response()
  def perp_deploy_auction_status(opts \\ []) do
    info_request(%{type: "perpDeployAuctionStatus"}, opts)
  end

  @doc """
  Fetch list of perpetuals at their open interest cap.

  ## Returns
    - `{:ok, coins}` - List of coin symbols
    - `{:error, %Error{}}` - Error with details
  """
  @spec perps_at_open_interest_cap(request_opts()) :: response()
  def perps_at_open_interest_cap(opts \\ []) do
    info_request(%{type: "perpsAtOpenInterestCap"}, opts)
  end

  @doc """
  Fetch predicted funding rates.

  ## Returns
    - `{:ok, predictions}` - Funding rate predictions
    - `{:error, %Error{}}` - Error with details
  """
  @spec predicted_fundings(request_opts()) :: response()
  def predicted_fundings(opts \\ []) do
    info_request(%{type: "predictedFundings"}, opts)
  end

  @doc """
  Fetch user's portfolio performance data.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, portfolio}` - Portfolio data across timeframes
    - `{:error, %Error{}}` - Error with details
  """
  @spec portfolio(String.t(), request_opts()) :: response()
  def portfolio(user, opts \\ []) do
    info_request(%{type: "portfolio", user: user}, opts)
  end

  @doc """
  Check if a transfer can be made.

  ## Parameters
    - `user`: User address (0x...)
    - `destination`: Destination address (0x...)
    - `amount`: Amount to transfer as string
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, check}` - Transfer check result
    - `{:error, %Error{}}` - Error with details
  """
  @spec pre_transfer_check(String.t(), String.t(), String.t(), request_opts()) :: response()
  def pre_transfer_check(user, destination, amount, opts \\ []) do
    info_request(
      %{type: "preTransferCheck", user: user, destination: destination, amount: amount},
      opts
    )
  end

  @doc """
  Fetch perpetuals metadata for a specific DEX.

  ## Parameters
    - `dex`: Optional DEX name (defaults to empty string for all)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, meta}` - Perpetuals metadata
    - `{:error, %Error{}}` - Error with details
  """
  @spec all_perp_metas(String.t() | nil, request_opts()) :: response()
  def all_perp_metas(dex \\ nil, opts \\ []) do
    info_request(%{type: "meta", dex: dex || ""}, opts)
  end

  @doc """
  Fetch active asset data for a user and coin.

  ## Parameters
    - `user`: User address (0x...)
    - `coin`: Coin symbol (e.g., "BTC")
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, data}` - Active asset data with leverage and limits
    - `{:error, %Error{}}` - Error with details
  """
  @spec active_asset_data(String.t(), String.t(), request_opts()) :: response()
  def active_asset_data(user, coin, opts \\ []) do
    info_request(%{type: "activeAssetData", user: user, coin: coin}, opts)
  end

  @doc """
  Fetch aligned quote token info.

  ## Parameters
    - `token`: Token index
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, info}` - Token alignment info
    - `{:error, %Error{}}` - Error with details
  """
  @spec aligned_quote_token_info(non_neg_integer(), request_opts()) :: response()
  def aligned_quote_token_info(token, opts \\ []) do
    info_request(%{type: "alignedQuoteTokenInfo", token: token}, opts)
  end

  @doc """
  Fetch block details.

  ## Parameters
    - `height`: Optional block height (nil for latest)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, block}` - Block details
    - `{:error, %Error{}}` - Error with details
  """
  @spec block_details(non_neg_integer() | nil, request_opts()) :: response()
  def block_details(height \\ nil, opts \\ []) do
    payload =
      if height, do: %{type: "blockDetails", height: height}, else: %{type: "blockDetails"}

    explorer_request(payload, opts)
  end

  @doc """
  Fetch user details from the explorer.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, user_details}` - User details
    - `{:error, %Error{}}` - Error with details
  """
  @spec user_details(String.t(), request_opts()) :: response()
  def user_details(user, opts \\ []) do
    explorer_request(%{type: "userDetails", user: user}, opts)
  end

  @doc """
  Fetch transaction details from the explorer.

  ## Parameters
    - `hash`: Transaction hash (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, tx_details}` - Transaction details
    - `{:error, %Error{}}` - Error with details
  """
  @spec tx_details(String.t(), request_opts()) :: response()
  def tx_details(hash, opts \\ []) do
    explorer_request(%{type: "txDetails", hash: hash}, opts)
  end

  @doc """
  Check if user is a VIP.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, status}` - VIP status
    - `{:error, %Error{}}` - Error with details
  """
  @spec is_vip(String.t(), request_opts()) :: response()
  def is_vip(user, opts \\ []) do
    info_request(%{type: "isVip", user: user}, opts)
  end

  @doc """
  Fetch user's historical orders.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, orders}` - List of historical orders
    - `{:error, %Error{}}` - Error with details
  """
  @spec historical_orders(String.t(), request_opts()) :: response()
  def historical_orders(user, opts \\ []) do
    info_request(%{type: "historicalOrders", user: user}, opts)
  end

  @doc """
  Fetch user's referral information.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, referral}` - Referral info and rewards
    - `{:error, %Error{}}` - Error with details
  """
  @spec referral(String.t(), request_opts()) :: response()
  def referral(user, opts \\ []) do
    info_request(%{type: "referral", user: user}, opts)
  end

  @doc """
  Fetch gossip network root IPs.

  ## Returns
    - `{:ok, ips}` - List of root IP addresses
    - `{:error, %Error{}}` - Error with details
  """
  @spec gossip_root_ips(request_opts()) :: response()
  def gossip_root_ips(opts \\ []) do
    info_request(%{type: "gossipRootIps"}, opts)
  end

  @doc """
  Fetch user's delegations.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, delegations}` - List of delegations
    - `{:error, %Error{}}` - Error with details
  """
  @spec delegations(String.t(), request_opts()) :: response()
  def delegations(user, opts \\ []) do
    info_request(%{type: "delegations", user: user}, opts)
  end

  @doc """
  Fetch user's delegator summary.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, summary}` - Delegator summary
    - `{:error, %Error{}}` - Error with details
  """
  @spec delegator_summary(String.t(), request_opts()) :: response()
  def delegator_summary(user, opts \\ []) do
    info_request(%{type: "delegatorSummary", user: user}, opts)
  end

  @doc """
  Fetch user's delegator history.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, history}` - Delegation history
    - `{:error, %Error{}}` - Error with details
  """
  @spec delegator_history(String.t(), request_opts()) :: response()
  def delegator_history(user, opts \\ []) do
    info_request(%{type: "delegatorHistory", user: user}, opts)
  end

  @doc """
  Fetch user's delegator rewards.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, rewards}` - Delegation rewards
    - `{:error, %Error{}}` - Error with details
  """
  @spec delegator_rewards(String.t(), request_opts()) :: response()
  def delegator_rewards(user, opts \\ []) do
    info_request(%{type: "delegatorRewards", user: user}, opts)
  end

  @doc """
  Fetch exchange status.

  ## Returns
    - `{:ok, status}` - Exchange operational status
    - `{:error, %Error{}}` - Error with details
  """
  @spec exchange_status(request_opts()) :: response()
  def exchange_status(opts \\ []) do
    info_request(%{type: "exchangeStatus"}, opts)
  end

  @doc """
  Fetch user's extra agents.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, agents}` - List of extra agents
    - `{:error, %Error{}}` - Error with details
  """
  @spec extra_agents(String.t(), request_opts()) :: response()
  def extra_agents(user, opts \\ []) do
    info_request(%{type: "extraAgents", user: user}, opts)
  end

  @doc """
  Fetch user's open orders with frontend info.

  ## Parameters
    - `user`: User address (0x...)
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, orders}` - Open orders with frontend display info
    - `{:error, %Error{}}` - Error with details
  """
  @spec frontend_open_orders(String.t(), request_opts()) :: response()
  def frontend_open_orders(user, opts \\ []) do
    info_request(%{type: "frontendOpenOrders", user: user}, opts)
  end

  @doc """
  Fetch leaderboard data from the stats API.

  ## Parameters
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, leaderboard}` - Leaderboard data with trader rankings
    - `{:error, %Error{}}` - Error with details
  """
  @spec leaderboard(request_opts()) :: response()
  def leaderboard(opts \\ []) do
    network = if Config.mainnet?(), do: "Mainnet", else: "Testnet"
    url = "#{Config.stats_base()}/#{network}/leaderboard"
    get(url, opts)
  end

  @doc """
  Fetch vaults data from the stats API.

  ## Parameters
    - `opts`: Optional HTTPoison options

  ## Returns
    - `{:ok, vaults}` - List of vaults with performance metrics
    - `{:error, %Error{}}` - Error with details
  """
  @spec vaults(request_opts()) :: response()
  def vaults(opts \\ []) do
    network = if Config.mainnet?(), do: "Mainnet", else: "Testnet"
    url = "#{Config.stats_base()}/#{network}/vaults"
    get(url, opts)
  end

  # ===================== Bang Methods =====================

  @doc """
  Fetch all mid prices. Raises on error.
  """
  def all_mids!(opts \\ []), do: unwrap!(all_mids(opts))

  @doc """
  Fetch perpetuals metadata. Raises on error.
  """
  def meta!(opts \\ []), do: unwrap!(meta(opts))

  @doc """
  Fetch spot metadata. Raises on error.
  """
  def spot_meta!(opts \\ []), do: unwrap!(spot_meta(opts))

  @doc """
  Fetch perpetuals metadata with asset contexts. Raises on error.
  """
  def meta_and_asset_ctxs!(opts \\ []), do: unwrap!(meta_and_asset_ctxs(opts))

  @doc """
  Fetch spot metadata with asset contexts. Raises on error.
  """
  def spot_meta_and_asset_ctxs!(opts \\ []), do: unwrap!(spot_meta_and_asset_ctxs(opts))

  @doc """
  Fetch user's perpetuals clearinghouse state. Raises on error.
  """
  def clearinghouse_state!(user, opts \\ []), do: unwrap!(clearinghouse_state(user, opts))

  @doc """
  Fetch user's spot clearinghouse state. Raises on error.
  """
  def spot_clearinghouse_state!(user, opts \\ []),
    do: unwrap!(spot_clearinghouse_state(user, opts))

  @doc """
  Fetch user's open orders. Raises on error.
  """
  def open_orders!(user, opts \\ []), do: unwrap!(open_orders(user, opts))

  @doc """
  Fetch user's order history. Raises on error.
  """
  def user_fills!(user, opts \\ []), do: unwrap!(user_fills(user, opts))

  @doc """
  Fetch funding history for a user. Raises on error.
  """
  def funding_history!(user, start_time, end_time \\ nil, opts \\ []) do
    unwrap!(funding_history(user, start_time, end_time, opts))
  end

  @doc """
  Fetch L2 order book snapshot. Raises on error.
  """
  def l2_book!(coin, opts \\ []), do: unwrap!(l2_book(coin, opts))

  @doc """
  Fetch recent trades for a coin. Raises on error.
  """
  def recent_trades!(coin, opts \\ []), do: unwrap!(recent_trades(coin, opts))

  @doc """
  Fetch candle data. Raises on error.
  """
  def candles!(coin, interval, start_time, end_time, opts \\ []) do
    unwrap!(candles(coin, interval, start_time, end_time, opts))
  end

  @doc """
  Fetch user's historical orders. Raises on error.
  """
  def historical_orders!(user, opts \\ []), do: unwrap!(historical_orders(user, opts))

  @doc """
  Fetch user's referral information. Raises on error.
  """
  def referral!(user, opts \\ []), do: unwrap!(referral(user, opts))

  @doc """
  Fetch exchange status. Raises on error.
  """
  def exchange_status!(opts \\ []), do: unwrap!(exchange_status(opts))

  @doc """
  Fetch user's extra agents. Raises on error.
  """
  def extra_agents!(user, opts \\ []), do: unwrap!(extra_agents(user, opts))

  @doc """
  Fetch user's open orders with frontend info. Raises on error.
  """
  def frontend_open_orders!(user, opts \\ []), do: unwrap!(frontend_open_orders(user, opts))

  @doc """
  Fetch user's portfolio performance data. Raises on error.
  """
  def portfolio!(user, opts \\ []), do: unwrap!(portfolio(user, opts))

  @doc """
  Fetch all perpetual DEXs. Raises on error.
  """
  def perp_dexs!(opts \\ []), do: unwrap!(perp_dexs(opts))

  @doc """
  Fetch predicted funding rates. Raises on error.
  """
  def predicted_fundings!(opts \\ []), do: unwrap!(predicted_fundings(opts))

  @doc """
  Fetch leaderboard data from the stats API. Raises on error.
  """
  def leaderboard!(opts \\ []), do: unwrap!(leaderboard(opts))

  @doc """
  Fetch vaults data from the stats API. Raises on error.
  """
  def vaults!(opts \\ []), do: unwrap!(vaults(opts))

  defp unwrap!({:ok, result}), do: result
  defp unwrap!({:error, %Error{} = error}), do: raise(error)
  defp unwrap!({:error, reason}), do: raise(Error.exception(%{reason: reason}))

  # ===================== Private Helpers =====================

  defp build_url(url) do
    if String.starts_with?(url, "http://") or String.starts_with?(url, "https://") do
      url
    else
      "#{Config.api_base()}#{url}"
    end
  end

  defp parse_response(body, raw?)

  defp parse_response(body, true) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, Error.exception(%{reason: {:json_decode_error, body}})}
    end
  end

  defp parse_response(body, false) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} ->
        {:ok, transform_keys(data)}

      {:error, _} ->
        {:error, Error.exception(%{reason: {:json_decode_error, body}})}
    end
  end

  # Transform camelCase keys to snake_case recursively
  defp transform_keys(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> {to_snake_case(k), transform_keys(v)} end)
    |> Enum.into(%{})
  end

  defp transform_keys(data) when is_list(data) do
    Enum.map(data, &transform_keys/1)
  end

  defp transform_keys(data), do: data

  # Single-character keys have no word boundary to split on. Downcasing them
  # would collapse distinct sibling keys into one — e.g. a candle's close time
  # "T" onto its open time "t" — silently dropping a field. Pass them through.
  defp to_snake_case(<<_::utf8>> = key), do: key

  defp to_snake_case(key) when is_binary(key) do
    key
    |> String.replace(~r/([A-Z])/, "_\\1")
    |> String.downcase()
    |> String.trim_leading("_")
  end

  defp to_snake_case(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> to_snake_case()
  end

  defp to_snake_case(key), do: key
end
