# Hyperliquid

[![Hex.pm](https://img.shields.io/hexpm/v/hyperliquid.svg)](https://hex.pm/packages/hyperliquid)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Elixir SDK for the Hyperliquid decentralized exchange with DSL-based API endpoints, WebSocket subscriptions, and optional Postgres/Phoenix integration.

## Overview

Hyperliquid provides a comprehensive, type-safe interface to the Hyperliquid DEX. The DSL-based architecture eliminates boilerplate while providing response validation, automatic caching, and optional database persistence. Endpoint coverage tracks the nktkas TypeScript SDK, including HIP-4 prediction markets.

## Features

- **DSL-based endpoint definitions** - Clean, declarative API with automatic function generation
- **165+ typed endpoints** - 78 Info endpoints, 60 Exchange actions, 31 WebSocket subscriptions
- **Ecto schema validation** - Built-in response validation and type safety
- **WebSocket connection pooling** - Efficient connection management with automatic reconnection
- **Cachex-based caching** - Fast in-memory asset metadata and mid price lookups
- **Optional Postgres persistence** - Config-driven database storage for API data
- **Testnet/mainnet support** - Easy chain switching with automatic database separation
- **Phoenix PubSub integration** - Real-time event broadcasting

## Installation

Add `hyperliquid` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hyperliquid, "~> 0.3.1"}
  ]
end
```

## Configuration

### Basic Configuration (No Database)

The minimal configuration requires only your private key:

```elixir
# config/config.exs
config :hyperliquid,
  private_key: "YOUR_PRIVATE_KEY_HERE"
```

### With Database Persistence

Enable database features by setting `enable_db: true` and adding the required dependencies:

```elixir
# mix.exs
defp deps do
  [
    {:hyperliquid, "~> 0.3.1"},
    # Required when enable_db: true
    {:phoenix_ecto, "~> 4.5"},
    {:ecto_sql, "~> 3.10"},
    {:postgrex, ">= 0.0.0"}
  ]
end
```

```elixir
# config/config.exs
config :hyperliquid,
  private_key: "YOUR_PRIVATE_KEY_HERE",
  enable_db: true

# Configure the Repo
config :hyperliquid, Hyperliquid.Repo,
  database: "hyperliquid_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool_size: 10
```

### Testnet Configuration

Switch to testnet and optionally disable automatic cache initialization:

```elixir
config :hyperliquid,
  chain: :testnet,
  private_key: "YOUR_TESTNET_KEY",
  autostart_cache: true  # Set to false to manually initialize cache
```

The database name automatically gets a `_testnet` suffix when using testnet.

### Advanced Configuration

```elixir
config :hyperliquid,
  # Chain selection
  chain: :mainnet,  # or :testnet

  # API endpoints (optional - defaults based on chain)
  http_url: "https://api.hyperliquid.xyz",
  ws_url: "wss://api.hyperliquid.xyz/ws",

  # Optional features
  enable_db: false,
  enable_web: false,
  autostart_cache: true,

  # Debug logging
  debug: false,

  # Private key
  private_key: "YOUR_PRIVATE_KEY_HERE",

  # EIP-712 domain chainId for user-signed actions (withdrawals, transfers,
  # agent approvals). Must match the signatureChainId sent in the action body —
  # the exchange rebuilds the domain from it to recover the signer, so if the two
  # disagree it recovers the wrong address and rejects the action. Both are read
  # from here, so they cannot drift.
  #
  # Defaults to 421_614 ("0x66eee"), matching the official Python SDK and the
  # nktkas TypeScript SDK. The Hyperliquid frontend uses 42_161 ("0xa4b1");
  # either works, as long as it is used consistently.
  signature_chain_id: 421_614,

  # szDecimals for HIP-4 outcome assets. outcomeMeta does not publish this and
  # outcome tokens are absent from spotMeta, so there is no authoritative source.
  # Too large a value makes the exchange reject the order, too small truncates
  # the size — confirm against a real outcome order before relying on it.
  outcome_sz_decimals: 2
```

### HIP-4 prediction markets

Outcome assets use their own encoding, derived from an outcome id plus a binary
side as `outcome * 10 + side`:

| representation | form | example |
| --- | --- | --- |
| spot coin | `#<encoding>` | `#70020` |
| token name | `+<encoding>` | `+70020` |
| asset ID | `100_000_000 + encoding` | `100070020` |

They appear in neither `spotMeta`'s universe nor its token list, so the cache
resolves them from `outcomeMeta`:

```elixir
Hyperliquid.Cache.outcome_coin(7002, 0)      # => "#70020"
Hyperliquid.Cache.outcome_asset(7002, 0)     # => 100070020
Hyperliquid.Cache.outcome_and_side("#70020") # => {:ok, {7002, 0}}
Hyperliquid.Cache.asset_from_coin("#70020")  # => 100070020

# Outcome coins work anywhere a coin is accepted
Hyperliquid.Api.Info.L2Book.request("#70020")
Hyperliquid.Api.Exchange.Order.limit_order("#70020", true, "0.5", "1")
```

## Quick Start

### Fetching Market Data

Use Info API endpoints to retrieve market data:

```elixir
# Get mid prices for all assets
alias Hyperliquid.Api.Info.AllMids

{:ok, mids} = AllMids.request()
# Returns raw map: %{"BTC" => "43250.5", "ETH" => "2280.75", ...}

# Get account summary
alias Hyperliquid.Api.Info.ClearinghouseState

{:ok, state} = ClearinghouseState.request("0x1234...")
state.margin_summary.account_value
# => "10000.0"

# Get open orders
alias Hyperliquid.Api.Info.FrontendOpenOrders

{:ok, orders} = FrontendOpenOrders.request("0x1234...")
# => [%{coin: "BTC", limit_px: "43000.0", ...}]

# Get user fills
alias Hyperliquid.Api.Info.UserFills

{:ok, fills} = UserFills.request("0x1234...")
# => %{fills: [%{coin: "BTC", px: "43100.5", ...}]}
```

### Placing Orders

Use Exchange API endpoints to trade. The private key defaults to the one in your config,
or you can pass it explicitly via the `:private_key` option:

```elixir
alias Hyperliquid.Api.Exchange.{Order, Cancel}

# Place a limit order (uses private_key from config)
{:ok, result} = Order.place_limit("BTC", true, "43000.0", "0.1")
# => %{status: "ok", response: %{data: %{statuses: [%{resting: %{oid: 12345}}]}}}

# Place a market order
{:ok, result} = Order.place_market("ETH", false, "1.5")

# Or build and place separately
order = Order.limit_order("BTC", true, "43000.0", "0.1")
{:ok, result} = Order.place(order)

# Override private key per-request
{:ok, result} = Order.place_limit("BTC", true, "43000.0", "0.1", private_key: other_key)

# Cancel an order by asset and order ID
{:ok, cancel_result} = Cancel.cancel(0, 12345)
# => %{status: "ok", response: %{data: %{statuses: ["success"]}}}
```

### Exchange Action Signing

Hyperliquid exchange actions use two different signing schemes:

- **Agent-key compatible** — Orders, cancels, leverage updates, and other trading actions use EIP-712 exchange domain signing. These can be signed with an **agent key** (approved via `ApproveAgent`) instead of your main private key. This is the recommended setup for trading bots.

- **L1-signed actions** — Transfers (`UsdClassTransfer`, `SubAccountTransfer`), withdrawals, vault operations, sub-account creation, and other account-level actions require your **actual private key**. These cannot be delegated to an agent key.

```elixir
# Agent-key compatible (trading actions)
# Configure your agent key in config and trade without exposing your main key
config :hyperliquid, private_key: "YOUR_AGENT_KEY"

Order.place_limit("BTC", true, "43000.0", "0.1")
Cancel.cancel(0, 12345)

# L1-signed actions (require main private key)
alias Hyperliquid.Api.Exchange.UsdClassTransfer
UsdClassTransfer.request(%{...}, private_key: "YOUR_MAIN_PRIVATE_KEY")
```

### WebSocket Subscriptions

Subscribe to real-time data feeds:

```elixir
alias Hyperliquid.WebSocket.Manager
alias Hyperliquid.Api.Subscription.{AllMids, Trades, UserFills}

# Subscribe to all mid prices (shared connection)
{:ok, sub_id} = Manager.subscribe(AllMids, %{})

# Subscribe to trades for BTC (shared connection)
{:ok, sub_id} = Manager.subscribe(Trades, %{coin: "BTC"})

# Subscribe to user fills (user-grouped connection)
{:ok, sub_id} = Manager.subscribe(UserFills, %{user: "0x1234..."})

# Unsubscribe
Manager.unsubscribe(sub_id)

# List active subscriptions
Manager.list_subscriptions()
```

### Using the Cache

The cache provides fast access to asset metadata and mid prices:

```elixir
alias Hyperliquid.Cache

# The cache auto-initializes on startup (unless autostart_cache: false)
# Manual initialization:
Cache.init()

# Get mid price for a coin
Cache.get_mid("BTC")
# => 43250.5

# Get asset index for a coin
Cache.asset_from_coin("BTC")
# => 0

Cache.asset_from_coin("HYPE/USDC")  # Spot pairs work too
# => 10107

# Get size decimals
Cache.decimals_from_coin("BTC")
# => 5

# Get token info
Cache.get_token_by_name("HFUN")
# => %{"name" => "HFUN", "index" => 2, "sz_decimals" => 2, ...}

# Subscribe to live mid price updates
{:ok, sub_id} = Cache.subscribe_to_mids()
```

## API Reference

### Info API (Market & Account Data)

The Info API provides read-only market and account information. All endpoints are located in `Hyperliquid.Api.Info.*`:

**Market Data:**
- `AllMids` - Mid prices for all assets
- `AllPerpMetas` - Perpetual market metadata
- `ActiveAssetData` - Asset context data
- `CandleSnapshot` - Historical candles
- `FundingHistory` - Funding rate history
- `L2Book` - Order book snapshot

**Account Data:**
- `ClearinghouseState` - Perpetuals account summary
- `SpotClearinghouseState` - Spot account summary
- `UserFills` - Trade fill history
- `HistoricalOrders` - Historical orders
- `FrontendOpenOrders` - Current open orders
- `UserFunding` - User funding payments

**Vault & Delegation:**
- `VaultDetails` - Vault information
- `Delegations` - User delegations
- `DelegatorRewards` - Delegation rewards

See the [HexDocs](https://hexdocs.pm/hyperliquid) for the complete list of 78 Info endpoints.

### Exchange API (Trading Operations)

The Exchange API handles all trading operations. All endpoints are located in `Hyperliquid.Api.Exchange.*`:

**Order Management:**
- `Modify` - Place or modify orders
- `BatchModify` - Batch order modifications
- `Cancel` - Cancel orders
- `CancelByCloid` - Cancel by client order ID

**Account Operations:**
- `UsdTransfer` - Transfer USD between accounts
- `Withdraw3` - Withdraw to L1
- `CreateSubAccount` - Create sub-accounts
- `UpdateLeverage` - Adjust position leverage
- `UpdateIsolatedMargin` - Modify isolated margin

**Vault Operations:**
- `CreateVault` - Create a new vault
- `VaultTransfer` - Vault deposits/withdrawals

See the [HexDocs](https://hexdocs.pm/hyperliquid) for the complete list of 60 Exchange actions.

### Subscription API (Real-time Updates)

The Subscription API provides WebSocket channels for real-time data. All endpoints are located in `Hyperliquid.Api.Subscription.*`:

**Market Subscriptions:**
- `AllMids` - All mid prices (shared connection)
- `Trades` - Recent trades (shared connection)
- `L2Book` - Order book updates (dedicated connection)
- `Candle` - Real-time candles (shared connection)

**User Subscriptions:**
- `UserFills` - User trade fills (user-grouped)
- `UserFundings` - Funding payments (user-grouped)
- `OrderUpdates` - Order status changes (user-grouped)
- `Notification` - User notifications (user-grouped)

**Explorer Subscriptions:**
- `ExplorerBlock` - New blocks (shared connection)
- `ExplorerTxs` - Transactions (shared connection)

See the [HexDocs](https://hexdocs.pm/hyperliquid) for the complete list of 31 subscription channels.

## Endpoint DSL

All API endpoints are defined using declarative macros that eliminate boilerplate:

### Info/Exchange Endpoints

```elixir
defmodule Hyperliquid.Api.Info.AllMids do
  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "allMids",
    optional_params: [:dex],
    rate_limit_cost: 2,
    raw_response: true

  embedded_schema do
    field(:mids, :map)
    field(:dex, :string)
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    # Validation logic
  end
end
```

This automatically generates:
- `request/0`, `request/1` - Make API request, return `{:ok, result}` or `{:error, reason}`
- `request!/0`, `request!/1` - Bang variant that raises on error
- `build_request/1` - Build request parameters
- `parse_response/1` - Parse and validate response
- `rate_limit_cost/0` - Get rate limit cost

### Subscription Endpoints

```elixir
defmodule Hyperliquid.Api.Subscription.Trades do
  use Hyperliquid.Api.SubscriptionEndpoint,
    request_type: "trades",
    params: [:coin],
    connection_type: :shared,
    storage: [
      postgres: [enabled: true, table: "trades"],
      cache: [enabled: true, ttl: :timer.minutes(5)]
    ]

  embedded_schema do
    embeds_many :trades, Trade do
      field(:coin, :string)
      field(:px, :string)
      # ...
    end
  end

  def changeset(event \\ %__MODULE__{}, attrs) do
    # Validation logic
  end
end
```

This automatically generates:
- `build_request/1` - Build subscription request
- `__subscription_info__/0` - Metadata about the subscription
- `generate_subscription_key/1` - Unique key for connection routing

## WebSocket Management

The `Hyperliquid.WebSocket.Manager` handles all WebSocket connections and subscriptions:

### Connection Strategies

- **`:shared`** - Multiple subscriptions share one connection (e.g., `AllMids`, `Trades`)
- **`:dedicated`** - Each subscription gets its own connection (e.g., `L2Book` with params)
- **`:user_grouped`** - All subscriptions for the same user share one connection (e.g., `UserFills`)

### Subscribe with Callbacks

```elixir
alias Hyperliquid.WebSocket.Manager
alias Hyperliquid.Api.Subscription.Trades

# Subscribe with callback function
callback = fn event ->
  IO.inspect(event, label: "Trade event")
end

{:ok, sub_id} = Manager.subscribe(Trades, %{coin: "BTC"}, callback)
```

### Phoenix PubSub Integration

All WebSocket events are broadcast via Phoenix.PubSub:

```elixir
# Subscribe to events in your LiveView or GenServer
Phoenix.PubSub.subscribe(Hyperliquid.PubSub, "ws_event")

# Or use the utility function
Hyperliquid.Utils.subscribe("ws_event")

# Handle events
def handle_info({:ws_event, event}, state) do
  # Process event
  {:noreply, state}
end
```

## Caching

The cache module provides efficient access to frequently-used data:

### Automatic Updates

When `autostart_cache: true` (default), the cache automatically:
- Fetches exchange metadata on startup
- Populates asset mappings and decimal precision
- Updates mid prices from WebSocket subscriptions

### Cache Functions

```elixir
alias Hyperliquid.Cache

# Asset lookups
Cache.asset_from_coin("BTC")         # => 0
Cache.decimals_from_coin("BTC")      # => 5
Cache.get_mid("BTC")                 # => 43250.5

# Metadata
Cache.perps()                        # => [%{"name" => "BTC", ...}, ...]
Cache.spot_pairs()                   # => [%{"name" => "@0", ...}, ...]
Cache.tokens()                       # => [%{"name" => "USDC", ...}, ...]

# Token lookups
Cache.get_token_by_name("HFUN")      # => %{"index" => 2, ...}
Cache.get_token_key("HFUN")          # => "HFUN:0xbaf265..."

# Low-level cache access
Cache.get(:all_mids)                 # => %{"BTC" => "43250.5", ...}
Cache.put(:my_key, value)
Cache.exists?(:my_key)               # => true
```

## Database Integration

When `enable_db: true`, the package provides Postgres persistence:

### Setup

```bash
# Install database dependencies
mix deps.get

# Create and migrate database
mix ecto.create
mix ecto.migrate
```

### Repo Configuration

```elixir
# config/config.exs
config :hyperliquid, ecto_repos: [Hyperliquid.Repo]

config :hyperliquid, Hyperliquid.Repo,
  database: "hyperliquid_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool_size: 10
```

### Storage Layer

Endpoints with `storage` configuration automatically persist data:

```elixir
# This subscription will automatically store trades in Postgres and Cachex
alias Hyperliquid.Api.Subscription.Trades

{:ok, sub_id} = Manager.subscribe(Trades, %{coin: "BTC"})

# Query stored data
import Ecto.Query
alias Hyperliquid.Repo

query = from t in "trades",
  where: t.coin == "BTC",
  order_by: [desc: t.time],
  limit: 10

Repo.all(query)
```

### Migrations

Database migrations are located in `priv/repo/migrations/`. The package includes migrations for:
- `trades`, `fills`, `orders`, `historical_orders`
- `clearinghouse_states`, `user_snapshots`
- `explorer_blocks`, `transactions`
- `candles`

## Livebook

Use Hyperliquid in Livebook for interactive trading and analysis:

```elixir
Mix.install([
  {:hyperliquid, "~> 0.3.1"}
],
config: [
  hyperliquid: [
    private_key: "YOUR_PRIVATE_KEY_HERE"
  ]
])

# Start working with the API
alias Hyperliquid.Api.Info.AllMids
{:ok, mids} = AllMids.request()
```

### Testnet in Livebook

```elixir
Mix.install([
  {:hyperliquid, "~> 0.3.1"}
],
config: [
  hyperliquid: [
    chain: :testnet,
    private_key: "YOUR_TESTNET_KEY"
  ]
])
```

## Explorer API

Query the Hyperliquid explorer for block and transaction details:

```elixir
alias Hyperliquid.Api.Explorer.{BlockDetails, TxDetails, UserDetails}

{:ok, block} = BlockDetails.request(block_height)
{:ok, tx} = TxDetails.request(tx_hash)
{:ok, user} = UserDetails.request("0x1234...")
```

## RPC Transport

Make JSON-RPC calls to the Hyperliquid EVM:

```elixir
alias Hyperliquid.Transport.Rpc

{:ok, block_number} = Rpc.call("eth_blockNumber", [])
{:ok, [block, chain]} = Rpc.batch([{"eth_blockNumber", []}, {"eth_chainId", []}])
```

## Telemetry

Hyperliquid emits `:telemetry` events for API requests, WebSocket connections, cache operations, RPC calls, and storage flushes. See `Hyperliquid.Telemetry` for the full event reference.

### Quick Debug Setup

```elixir
Hyperliquid.Telemetry.attach_default_logger()
```

### Telemetry.Metrics Example

```elixir
defmodule MyApp.Telemetry do
  import Telemetry.Metrics

  def metrics do
    [
      summary("hyperliquid.api.request.stop.duration", unit: {:native, :millisecond}),
      summary("hyperliquid.api.exchange.stop.duration", unit: {:native, :millisecond}),
      counter("hyperliquid.ws.message.received.count"),
      summary("hyperliquid.rpc.request.stop.duration", unit: {:native, :millisecond}),
      last_value("hyperliquid.storage.flush.stop.record_count")
    ]
  end
end
```

## Development

```bash
# Get dependencies
mix deps.get

# Run tests
mix test

# Run tests with database
mix test

# Format code
mix format

# Generate docs
mix docs
```

## Documentation

Full documentation is available on [HexDocs](https://hexdocs.pm/hyperliquid).

## License

This project is licensed under the MIT License. See [LICENSE.md](LICENSE.md) for details.
