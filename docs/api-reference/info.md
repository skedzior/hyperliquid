# Info API

The Info API provides read-only market and account data. All modules are under `Hyperliquid.Api.Info.*`.

Every endpoint exposes:
- `request/N` - Returns `{:ok, result}` or `{:error, Hyperliquid.Error.t()}`
- `request!/N` - Returns result directly or raises

## Market Data

| Module | Parameters | Description |
|--------|-----------|-------------|
| `AllMids` | `opts \\ []` | Mid prices for all assets |
| `AllPerpMetas` | - | Perpetual market metadata |
| `ActiveAssetData` | `user, asset` | Asset context for user |
| `CandleSnapshot` | `coin, interval, start_time, end_time` | Historical candles |
| `FundingHistory` | `coin, start_time, end_time` | Funding rate history |
| `L2Book` | `coin` | Order book snapshot |
| `Meta` | - | Exchange metadata |
| `MetaAndAssetCtxs` | - | Metadata with asset contexts |
| `SpotMeta` | - | Spot market metadata |
| `SpotMetaAndAssetCtxs` | - | Spot metadata with contexts |

## Account Data

| Module | Parameters | Description |
|--------|-----------|-------------|
| `ClearinghouseState` | `user` | Perpetuals account summary |
| `SpotClearinghouseState` | `user` | Spot account summary |
| `UserFills` | `user` | Trade fill history |
| `UserFillsByTime` | `user, start_time, opts` | Fills in time range |
| `HistoricalOrders` | `user` | Historical orders |
| `FrontendOpenOrders` | `user` | Current open orders |
| `OpenOrders` | `user` | Open orders (raw) |
| `UserFunding` | `user, start_time, end_time` | Funding payments |
| `UserRateLimit` | `user` | Rate limit status |
| `MaxBuilderFee` | `user, builder` | Max builder fee |
| `OrderStatus` | `user, oid` | Single order status |

## Vault & Delegation

| Module | Parameters | Description |
|--------|-----------|-------------|
| `VaultDetails` | `vault_address` | Vault information |
| `Delegations` | `user` | User delegations |
| `DelegatorRewards` | `user` | Delegation rewards |
| `DelegatorHistory` | `user` | Delegation history |
| `DelegatorSummary` | `user` | Delegation summary |

## HIP-4 / Outcome Markets

| Module | Parameters | Description |
|--------|-----------|-------------|
| `OutcomeTemplates` | - | Outcome-market templates available to deployers |
| `OutcomeMeta` | - | Metadata for all deployed outcome markets |
| `SettledOutcome` | `outcome` | Settlement result for one outcome |
| `OutcomeDeployerLimits` | `user` | Deployer limits (untyped passthrough - no upstream type) |

`SettledOutcome.request/1` answers `{:ok, nil}` when the outcome is not settled
yet (the API returns `null`), as does `VaultDetails.request/1` for a vault
address that does not exist.

Live updates for these markets come from the `outcomeMetaUpdates` subscription -
see [Subscription API](subscriptions.md). The deployer and user actions live in
[HIP-4 Outcome Markets](../guides/hip-4-outcome-markets.md).

## Usage

```elixir
alias Hyperliquid.Api.Info.AllMids

# Standard call
{:ok, mids} = AllMids.request()

# Bang variant (raises on error)
mids = AllMids.request!()

# With optional params
{:ok, mids} = AllMids.request(dex: "hyperliquid")
```

For the complete list of 79 Info endpoints, see the [HexDocs](https://hexdocs.pm/hyperliquid).
