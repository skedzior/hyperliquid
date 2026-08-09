# Changelog

## 0.4.1

### Fixed

- `outcome_sz_decimals` defaulted to `2`, but outcome assets take whole-number
  sizes only. Any size the formatter emitted with decimals was rejected by the
  exchange with "Order has invalid size", so outcome orders could not be placed
  with the default. Now `0`.

  Confirmed on testnet against asset `100102190`: sizes of `1000` and `1001`
  passed validation (IOC, no match), while `1000.5` and `1000.05` were both
  rejected. The docs do not publish this — neither the HIP-4 page nor the
  asset-ids page mentions `szDecimals` for outcomes, `outcomeMeta` omits it, and
  outcome tokens are absent from `spotMeta`.

## 0.4.0

### Added

- **HIP-4 outcome assets are now resolvable.** Outcome coins appear in neither
  `spotMeta`'s universe nor its token list, so `asset_map` held none of them and
  `Order.limit_order("#102190", ...)` failed with `{:coin_not_found, ...}` —
  outcome markets could be watched but not traded. `Cache.init/0` now fetches
  `outcomeMeta` and expands each outcome into its two sides using the documented
  encoding (`outcome * 10 + side` → coin `#<encoding>`, asset
  `100_000_000 + encoding`). Validated against testnet: the 309 live outcomes
  expand to exactly the 618 `#`-prefixed coins `allMids` returns.
- `Cache.outcome_coin/2`, `outcome_asset/2`, `outcome_and_side/1`,
  `outcome_coin?/1`, `outcome_asset?/1`, `outcome_asset_base/0`.
- `config :hyperliquid, outcome_sz_decimals: N` (default 0). Outcome sizes are
  whole numbers, confirmed on testnet: sizes of 1000 and 1001 passed validation
  while 1000.5 and 1000.05 were rejected with "Order has invalid size." No
  endpoint publishes this, so it stays configurable in case it varies per outcome
  or changes on a network upgrade.
- Six further node info endpoints, verified against a live node:
  `gossipPriorityAuctionStatus`, `perpConciseAnnotations`, `outcomeMeta`,
  `outcomeTemplates`, `perpDexStatus`, `settledOutcome`.
- WebSocket connection rate limiting in `WebSocket.Manager`, covering both the
  connection count and a new-connections-per-minute window, including on the
  replace path when a connection dies.

- Added `Hyperliquid.Node` module for interacting with local Hyperliquid node endpoints
- 47 generated convenience functions for node-verified local info endpoints with struct parsing
- Added 7 new endpoints: `allPerpMetas`, `allBorrowLendReserveStates`, `spotPairDeployAuctionStatus`, `subAccounts2`, `userDexAbstraction`, `alignedQuoteTokenInfo`, `perpDexLimits`
- Added 6 more node-verified info endpoints: `perpCategories`, `userAbstraction`, `approvedBuilders`, `borrowLendUserState`, `borrowLendReserveState`, `perpAnnotation`
- Optional `dex:` keyword arg support on `meta`, `clearinghouseState`, `openOrders`, `frontendOpenOrders`, `perpsAtOpenInterestCap`
- Refactored `@supported_endpoints` to 5-tuple format `{name, type, mod, required, optional}` for clean optional param generation
- Fixed `marginTable` to accept required `id` parameter
- Added generic single-param macro case for non-user params (`id`, `token`, `dex`)
- Documented full list of supported and unsupported local node endpoints
- Added new exchange endpoints: `BorrowLend`, `PerpDeploy`, `SpotDeploy`, `SpotUser`, `UserDexAbstraction`, `UserPortfolioMargin`
- Added new info endpoint: `UserBorrowLendInterest`
- Added new WebSocket subscriptions: `AllDexsAssetCtxs`, `AllDexsClearinghouseState`
- Generic `info_request/2` fallback for undocumented or future node endpoints
- File snapshot helpers (`file_snapshot/3`, `referrer_states_snapshot/2`, `l4_snapshots/2`)
- EVM RPC helpers via `:node` named RPC (`rpc_call/2`, `rpc_call!/2`)
- Added `node_info_request/2` to `Hyperliquid.Transport.Http`
- Independent `enable_node_info` and `enable_node_rpc` config flags
- Added `node_url/0`, `node_rpc_enabled?/0`, `node_info_enabled?/0` to `Hyperliquid.Config`

### Fixed

- `query_asset/1` returned `nil` for outcome assets, falling through to the perp
  lookup; it gains an `:outcome` branch.
- Two copies of an inline range check classified outcome assets as perps,
  allowing 6 price decimals instead of the spot-like 8. Replaced with
  `max_decimals_for_asset/1`.
- The success check in `Cache.init_with_partial_success/0` counted against a
  literal `4`, so adding a fifth data source would have reported every full
  success as partial.

### Notes

Two entries in the documented node support table were wrong, corrected by
probing a live node against all 78 info request types (it serves 48):

- `perpDexStatus` was listed as unsupported. The node serves it.
- `alignedQuoteTokenInfo` was listed as supported. The node rejects it.

`borrowLendReserveState` requires an **integer** token. The node returns the same
deserialization error for an unknown request type and a malformed one, so a wrong
param type is indistinguishable from an unsupported endpoint.

## 0.3.1

### Changed

- **User-signed actions now sign with `signatureChainId` `0x66eee` (421614).**
  The EIP-712 domain's `chainId` and the action's `signatureChainId` must agree,
  because the exchange rebuilds the domain from `signatureChainId` to recover the
  signer. They did agree before, at `0xa4b1` (42161), so signatures verified —
  but that diverged from the official Python SDK and the nktkas TypeScript SDK,
  which both use `0x66eee`. Signatures are now byte-comparable with both.

  Both values are accepted by the exchange; only self-consistency matters. The
  Hyperliquid frontend itself sends `0xa4b1` (see
  `test/debug/send_asset_debug_test.exs`, built from captured payloads). Set
  `config :hyperliquid, signature_chain_id: 42_161` to restore the previous
  behaviour.

### Fixed

- The `usdSend` EIP-712 test vector now passes. It had asserted the reference
  SDKs' `0x66eee` signature while the library signed with `0xa4b1`.

### Added

- `Hyperliquid.Config.signature_chain_id/0` and `signature_chain_id_hex/0` — a
  single source of truth for a value that was previously hardcoded in the Rust
  NIF and in a dozen Elixir modules independently. That duplication is what
  allowed the domain and `signatureChainId` to drift apart before `e0e67bf`.
- `Hyperliquid.Api.Exchange.UserSigned` — shared EIP-712 domain and signing for
  user-signed actions. The five actions that previously signed through
  specialized Rust NIFs (`usdSend`, `withdraw3`, `spotSend`, `approveAgent`,
  `approveBuilderFee`) now go through it, so configuration reaches them.
  Verified byte-identical to the NIF path before switching.

### Upgrade notes

Precompiled NIFs are rebuilt for this release: the Rust `chain/1` default moved
to 421614 so the standalone `Signer.sign_*` functions stay in step with
`Config.signature_chain_id/0`.

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
