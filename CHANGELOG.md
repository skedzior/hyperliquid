# Changelog

## Unreleased

Relative to **0.4.1**. Endpoint coverage is re-synced to `@nktkas/hyperliquid`
v0.33.3 plus the official HIP-4 docs (**79 Info endpoints, 60 Exchange actions,
31 WebSocket subscriptions**, 3 Explorer and 2 Stats), and this lands the fixes
for the **High** findings of the 2026-09-08 architecture & design review, which
are signing-, transport-, WebSocket- and storage-wide. Read the Breaking changes
before upgrading.

### Breaking changes

- **`/exchange` rejections are now errors.** Hyperliquid answers rejected and
  partially-rejected orders with HTTP 200. Calls that previously returned
  `{:ok, %{"status" => "err", …}}`, or `{:ok, _}` with a rejected item inside
  `response.data.statuses`, now return
  `{:error, %Hyperliquid.Error{type: :exchange | :partial_rejection}}`; bang
  variants raise. `error.response` carries the raw envelope and
  `error.statuses` the full per-item list, accepted items included.
- **Five actions are user-signed EIP-712, not L1 msgpack** — `usdClassTransfer`,
  `userPortfolioMargin`, `userDexAbstraction`, `linkStakingUser` and
  `convertToMultiSigUser`. All five built and msgpack-hashed an L1 action, and
  all five had the wrong fields, so their signatures could never have recovered
  to the sending address. They now go through
  `Hyperliquid.Api.Exchange.UserSigned` with the field lists
  `@nktkas/hyperliquid` declares (and, where it implements them,
  `hyperliquid-python-sdk`). Every call signature changed:

  | Module | Was | Now | `primaryType` / signed fields |
  |---|---|---|---|
  | `UsdClassTransfer` | `request(amount, to_perp, opts)` as an L1 action accepting `:vault_address` | `request(amount, to_perp, opts)`, no `:vault_address` | `HyperliquidTransaction:UsdClassTransfer` — `amount` (string), `toPerp` (bool), `nonce` |
  | `UserPortfolioMargin` | `request(on, opts)` — sent `{type, on}` | `request(user, enabled, opts)` | `HyperliquidTransaction:UserPortfolioMargin` — `user` (address), `enabled` (bool), `nonce` |
  | `UserDexAbstraction` | `request(enabled, opts)` — no `user` at all | `request(user, enabled, opts)` | `HyperliquidTransaction:UserDexAbstraction` — `user` (address), `enabled` (bool), `nonce` |
  | `LinkStakingUser` | `request(link_to, opts)` — sent a `linkTo` field that does not exist on the wire | `request(user, is_finalize, opts)` | `HyperliquidTransaction:LinkStakingUser` — `user` (address), `isFinalize` (bool), `nonce` |
  | `ConvertToMultiSigUser` | `request(authorized_users, threshold, opts)` — inlined `{authorizedUsers, threshold}` into the action | `request(signers, opts)`, where `signers` is `%{authorized_users:, threshold:}`, `nil` (revert to single-sig), or a pre-rendered JSON string | `HyperliquidTransaction:ConvertToMultiSigUser` — `signers` (string), `nonce` |

  `signers` is signed as an opaque string, so the exact JSON text is part of the
  signature: `ConvertToMultiSigUser.encode_signers/1` renders `authorizedUsers`
  (sorted, lowercased) before `threshold` with no whitespace, matching
  `JSON.stringify` in nktkas. None of the five accepts `:vault_address` any
  more — user-signed actions have no vault or `expiresAfter` slot.
- **Three user-signed actions had the wrong EIP-712 struct.** Each built its own
  typed data inline and disagreed with `@nktkas/hyperliquid` on field names,
  declaration order or Solidity types. All three feed the EIP-712 type hash and
  the encoded struct, so the old signatures could never have recovered to the
  sending address:

  | Module | Defect | Now |
  |---|---|---|
  | `TokenDelegate` | `validator` typed `string`, and `isUndelegate` declared before `wei` | `validator` (address), `wei` (uint64), `isUndelegate` (bool), `nonce` (uint64) |
  | `UserSetAbstraction` | the `user` field was missing entirely | `user` (address), `abstraction` (string), `nonce` (uint64) |
  | `SendToEvmWithData` | `destinationChainId` typed `uint64`, `data` typed `string` | `destinationChainId` (uint32), `data` (bytes) |

  Only `UserSetAbstraction` changes its public arity, because the missing field
  has to be supplied by the caller: `request(abstraction, opts)` becomes
  **`request(user, abstraction, opts)`**.
- **Hex values are lower-cased before hashing.** Hyperliquid lower-cases every
  `0x…` string when it deserializes an action into its own structs, and it is
  that re-serialization the signature is checked against, so a checksummed
  address recovered a garbage signer ("User or API Wallet 0x… does not exist"
  naming an address nobody has ever used). Normalized in both
  `Hyperliquid.Api.Exchange.Action` and `UserSigned`, matching nktkas's `Hex`
  schema. Verified live on testnet.
- **WebSocket subscribe behaviour changed.** `Connection.subscribe/3` and
  `unsubscribe/2` are casts and connecting is fully asynchronous, so
  `Manager.subscribe/3` no longer blocks on a TCP+TLS handshake. Callbacks run
  in a per-subscription process rather than inline on the singleton Manager, and
  a subscription with **no** callback now delivers
  `{:hyperliquid_ws, subscription_id, message}` to the subscribing process
  (previously it received nothing). Events are demultiplexed by the full
  subscription identity, so a subscriber no longer receives another
  subscription's data. The subscribing process is monitored and its
  subscriptions are torn down when it exits.
- **WebSocket limit config keys changed.** `:ws_max_users` is retired — it
  modelled a global budget of 10 users, which was never the real cap. Replaced
  by `:ws_max_users_per_connection` (default **15**, the empirically verified
  per-connection server cap) and `:ws_user_linger_ms` (default `15_000`).
  `:ws_max_connections` / `:ws_max_subscriptions` are superseded by
  `:ws_max_connections_per_ip` (default **100**, was 10) and
  `:ws_max_subscriptions_per_ip` (default 1000); the old keys are still honoured
  when set. Added `:ws_max_messages_per_second` (50) and
  `:ws_resubscribe_batch_size` (20). All are read through `Hyperliquid.Config`
  and surfaced by `Hyperliquid.WebSocket.Limits`.
- **`Cache.Warmer.initialized?/0` means *fully* warmed.** A partial warm-up now
  answers `false` and is retried with exponential backoff instead of being
  latched as success. Use `Warmer.warm_status/0`
  (`:pending | :ok | :partial | :failed`) to accept degraded data.
- **Default HTTP timeouts dropped from 30s/30s to 5s connect / 15s recv**
  (`:http_connect_timeout`, `:http_recv_timeout`). Reads now retry up to 3 times
  on 429/5xx/transport blips, so a failing read can take longer before it
  returns; set `http_max_retries: 0` to restore the old behaviour. `/exchange`
  writes are never retried.
- **`to_snake_case/1` no longer rewrites data keys.** 0.3.0 stopped single-letter
  keys collapsing (candle `"T"` onto `"t"`), but all-caps and mixed-case *data*
  keys were still mangled — `allMids` returned `"b_t_c"` and `"k_p_e_p_e"`. A key
  is now rewritten only when it is unambiguously a camelCase field name. Any
  caller that adapted to the mangled form must be updated.
- **`mix hyperliquid.gen.schemas` is removed.** Its generators emitted
  `# Fields will be generated here` yet called `File.write!/2` unconditionally
  into `lib/hyperliquid/api/<category>/<endpoint>.ex` — running it with no flags
  would have destroyed ~130 hand-written endpoint modules. Nothing referenced it.
  Replaced by `mix hyperliquid.gen.migrations`.
- **The signing NIF's ABI changed.** The typed `Actions` enum is gone — every L1
  action is hashed from the caller-supplied JSON, so Elixir owns key order and
  adding an action needs no Rust change — and the msgpack/keccak NIFs moved to
  dirty CPU schedulers. Two musl targets (`x86_64-unknown-linux-musl`,
  `aarch64-unknown-linux-musl`) were added to `signer.ex` and the
  `nif_build.yml` matrix. `checksum-Elixir.Hyperliquid.Signer.exs` is therefore
  stale and must be regenerated at release (see below).
- `mix test` is offline by default. `test/test_helper.exs` excludes
  `:requires_database` and `:network` unconditionally, `config/test.exs` disables
  the DB and the cache warmer, and the `test:` alias only runs
  `ecto.create`/`ecto.migrate` when `HYPERLIQUID_TEST_DB=1`. Opt back in with
  `HYPERLIQUID_TEST_DB=1` / `HYPERLIQUID_TEST_NETWORK=1`.

### Added

- **`Hyperliquid.Api.MultiSig`** — build, sign and send `multiSig` wrapper
  actions for both L1 and user-signed inner actions. 0.4.1 exposed only the
  `sign_multi_sig_action_ex` NIF and had no Elixir action module.
- **HIP-4 deployment and outcome actions**: `Exchange.OutcomeDeploy` (top-level
  `outcomeDeploy` with a required `venue`; all six operations including
  `setSubDeployers`) and `Exchange.UserOutcome`
  (`split` / `merge` / `mergeQuestion` / `negate`), plus the
  `outcomeDeployerLimits` info endpoint (untyped passthrough — there is no
  upstream type to pin it against).
- **`fastAssetCtxs` events are decoded.** The server pushes each update as a
  base64 + raw DEFLATE (RFC 1951) string; 0.4.1 stored that string verbatim.
  Subscription modules may now define `preprocess/1`, applied to the `"data"`
  half of each event before storage and callbacks, and `FastAssetCtxs` uses it
  to inflate the payload. First message is a snapshot, later messages are deltas
  to be folded in with `FastAssetCtxs.merge/2`.
- **WebSocket control/data-plane split**: `WebSocket.Budget`, `Limits`,
  `Packer`, `Store`, `Subscriber` and `SubscriptionKey`. The packer places
  user-scoped subscriptions across connections under the 15-unique-users-per-
  connection cap instead of rejecting them, and `SubscriptionKey` gives every
  subscription a full identity to demultiplex on.
- **`Storage.Writer` backpressure**: bounded queues with an explicit
  drop-oldest policy (default 10_000), dropping at the source and counting what
  was dropped, rather than growing the mailbox without limit.
- `mix hyperliquid.gen.migrations` — generates the Ecto migrations that were
  previously hand-written and checked in.
- `.github/workflows/ci.yml` — format, compile-with-warnings-as-errors, test,
  `cargo fmt`/`clippy`, and a strict NIF checksum gate on every push and PR.
  `nif_build.yml` gains a bootstrap escape hatch so the first tag of a new
  version, which cannot yet have a checksum file, does not fail.
- **Cross-SDK signing vectors**: `test/signing_vectors_test.exs` and
  `test/api/exchange/user_signed_vectors_test.exs`, generated from the reference
  Python SDK by `scripts/gen_signing_vectors.py` /
  `scripts/emit_signing_vectors_test.py`, plus live testnet matrices
  (`scripts/testnet_smoke.exs`, `scripts/testnet_smoke_master.exs`,
  `scripts/mainnet_smoke.exs`) and `scripts/verify_nif_checksums.exs`.
- Exchange actions `agentSendAsset`, `authorizeAqav2Role`,
  `finalizeEvmContract`, `gossipPriorityBid`, `hip3LiquidatorTransfer`,
  `topUpIsolatedOnlyMargin` and the user-signed
  `stakingLinkDisableTradingUser`; `perpDeploy` gains `setDeployerFees`,
  `setPerpAnnotation` and `disableDex`; `spotDeploy` gains `disableQuoteToken`,
  `disableAlignedQuoteToken`, `setTokenAnnotation` and `setDeployerLabel`, for
  all 12 documented variants.
- `twapOrder` optional `:details` (trigger / stop price), appended after `t` and
  omitted when unset; `order` gains an `:extra` passthrough on trigger orders, a
  forward-compat seam for trailing stops whose API shape is unpublished;
  `cancel` / `cancelByCloid` gain the `:fast` option (`f`);
  `reserveRequestWeight` gains optional `:destination`.
- Info field gaps closed: `marginTable` optional `dex`; `userFills` /
  `userFillsByTime` gain `builderFee`, `feeTrialEscrow`, `twapId`, `cloid` and
  the `liquidation` embed (whose `liquidatedUser` is optional);
  `spotClearinghouseState` gains `tokenToSupplyRatio`,
  `tokenToPortfolioSupplyRatio`, `tokenToAvailableAfterMaintenance` and
  `outcome_id/1`; `subAccounts2` and `webData3` gain `abstraction`; `legalCheck`
  gains `restrictions`; `twapHistory` gains `stopPx`, `trigger`, the
  `waitingForTrigger`/`stopped` statuses and `waiting_for_trigger/1` +
  `pending/1`; `validatorL1Votes` keeps structured HIP-4 vote payloads in
  `vote_data`; `explorer/userDetails` accepts a positional `action` list.
- `Cache.mids_age_ms/0` and `mids_stale?/1`, for refusing to price a market
  order off a stale snapshot when the mids subscription has died.

### Fixed

- `vaultTransfer` sent `usd` as a string; the API requires an integer.
  `vaultDistribute` omitted `usd` entirely. `subAccounts` / `subAccounts2`
  returned a changeset error instead of an empty list when the API answers
  `null` for a user with no sub-accounts.
- `cDeposit` / `cWithdraw` indexed the raw NIF result as a map without checking
  it, raising on a signing failure instead of returning `{:error, _}`. They,
  `sendAsset` and `stakingLinkDisableTradingUser` now route through `UserSigned`
  as well, so the domain, the configurable `signatureChainId` and the
  `hyperliquidChain` assembly all come from one place.
- L1 action field order moved from `ActionEncoder`'s single global key ranking
  to per-action-type schemas transcribed from the nktkas valibot request
  schemas, in `Hyperliquid.Api.Exchange.Action`. A global ranking is only
  correct while no key needs a different relative position in two shapes, which
  has no reason to hold for every action Hyperliquid adds.
  `Hyperliquid.Api.ActionEncoder` is kept as the encoding entry point and
  delegates to it. Keys the schemas do not declare are sorted lexicographically
  when they came from a plain Elixir map (whose key order follows the per-boot
  atom table) and left alone when the caller supplied an explicit
  `Jason.OrderedObject`.

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
