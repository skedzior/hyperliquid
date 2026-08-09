# Changelog

## 0.3.0

### Fixed

- **L1 action signing was non-deterministic.** The connection id is the keccak of
  the action's msgpack encoding, and msgpack preserves field order, so field order
  is part of the signed preimage. Actions were encoded straight from Elixir maps,
  which do not preserve insertion order — for atom keys the order follows the atom
  table, which is populated differently on every BEAM run. The same action hashed
  to a different connection id on each boot. Added `Hyperliquid.Api.ActionEncoder`,
  which renders actions in canonical field order; the signed preimage and the
  request body are now built from the same canonicalized value. Verified against
  the reference Python SDK.
- Candle close time (`T`) was silently destroyed. `to_snake_case/1` downcased a
  lone uppercase letter, collapsing `"T"` onto `"t"`. Affected every non-raw HTTP
  response, and fixed at all four key-transform sites. Thanks @code-supply (#7).
- `clearinghouseState` subscriptions could not target the main perps dex.
  `validate_required/2` treats `""` as missing, which is the documented default.
  `dex` is now optional. Thanks @code-supply (#8).

### Added

- Full endpoint parity with the nktkas TypeScript SDK (v0.33.3): 78 info
  endpoints, 60 exchange actions, 31 subscription channels.
- HIP-4 prediction markets: `outcomeMeta`, `outcomeTemplates`, `settledOutcome`,
  `activateOutcomeDeployer`, `userOutcome`, `outcomeMetaUpdates`.
- Gossip priority and routing: `gossipPriorityAuctionStatus`, `gossipPriorityBid`,
  `usdcRouting`, `perpConciseAnnotations`, `fastAssetCtxs`.
- Exchange actions: `agentSendAsset`, `authorizeAqav2Role`, `finalizeEvmContract`,
  `hip3LiquidatorTransfer`, `topUpIsolatedOnlyMargin`,
  `stakingLinkDisableTradingUser`.
- Order priority fees: `grouping` accepts `{:priority, rate}`, serialized as
  `{"p": rate}` where the rate is the fraction `rate / 1e8`.
- Documented the `FrontendMarket` time-in-force.

### Changed

- Updated rustler to 0.38. Requires the `init!` NIF list to be dropped (0.38
  auto-registers `#[rustler::nif]` functions) and the Rust crate bumped to match.
- Fixed local NIF builds: `crate: "signer_nif"` resolved to `native/signer_nif`,
  but the crate lives in `native/signer`, so `HYPERLIQUID_BUILD_NIF=1` never
  worked. Thanks @code-supply (#9).
- Tests requiring a from-source NIF are tagged `:requires_native_build` and
  excluded unless `HYPERLIQUID_BUILD_NIF=1`.

### Upgrade notes

Precompiled NIFs are rebuilt for this release. Anyone vendoring the 0.2.2
artifacts must take the 0.3.0 ones — the older binaries reject priority grouping
with `invalid type: map, expected a string`.

## 0.2.0

- Complete DSL migration: all endpoints defined via declarative macros (`use Endpoint`, `use SubscriptionEndpoint`)
- 62 Info endpoints, 38 Exchange endpoints, 26 WebSocket subscription channels
- Added Explorer API modules (`BlockDetails`, `TxDetails`, `UserDetails`) and Stats modules
- Added `Hyperliquid.Telemetry` with events for API, WebSocket, cache, RPC, and storage
- Added `:telemetry` instrumentation to WebSocket connection/manager, cache init, RPC transport, and storage writer
- Added `Hyperliquid.Transport.Rpc` for JSON-RPC calls to the Hyperliquid EVM
- Ecto schema validation and optional Postgres persistence for subscription data
- Private key is now optional with config fallback and address validation
- Fixed EIP-712 domain name and chainId for all exchange modules
- Normalized market order prices to tick size in asset-based builder

## 0.1.6

- Updated l2Book post req to include sigFig and mantissa values

## 0.1.5

- Added new userFillsByTime endpoint to info context

## 0.1.4

- Added nSigFigs and mantissa optional params to l2Book subscription, add streamer pid to msg

## 0.1.3

- Added functions to cache for easier access and allow intellisense to help you see what's available
