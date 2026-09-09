# Exchange API

The Exchange API handles trading operations and account management. All modules are under `Hyperliquid.Api.Exchange.*`.

All exchange actions require a private key for signing. The key defaults to the one in your config, or can be passed per-request via the `:private_key` option.

## Signing Modes

- **`:exchange` signing** - Orders, cancels, leverage changes. Can use an agent key approved via `ApproveAgent`.
- **`:l1` signing** - Transfers, withdrawals, vault operations, sub-account creation. Requires your main private key.

## Order Management

| Module | Description |
|--------|-------------|
| `Order` | Place orders (limit, market, trigger) |
| `Modify` | Modify existing orders |
| `BatchModify` | Batch order modifications |
| `Cancel` | Cancel orders by asset + OID |
| `CancelByCloid` | Cancel by client order ID |

### Order Helpers

```elixir
alias Hyperliquid.Api.Exchange.Order

# Limit order
{:ok, result} = Order.place_limit("BTC", true, "43000.0", "0.1")

# Market order
{:ok, result} = Order.place_market("ETH", false, "1.5")

# Trigger (stop) order
{:ok, result} = Order.place_trigger("BTC", true, "42000.0", "0.1",
  trigger_px: "41500.0", tp_sl: "sl")

# Build order structs manually
order = Order.limit_order("BTC", true, "43000.0", "0.1")
{:ok, result} = Order.place(order)

# Batch orders
{:ok, result} = Order.place_batch([order1, order2], "na")
```

## Account Operations

| Module | Signing | Description |
|--------|---------|-------------|
| `UpdateLeverage` | `:exchange` | Change position leverage |
| `UpdateIsolatedMargin` | `:exchange` | Modify isolated margin |
| `UsdClassTransfer` | `:l1` | Transfer USD between accounts |
| `Withdraw3` | `:l1` | Withdraw to L1 |
| `SpotSend` | `:l1` | Send spot tokens |
| `CreateSubAccount` | `:l1` | Create sub-accounts |
| `SubAccountTransfer` | `:l1` | Transfer between sub-accounts |
| `ApproveAgent` | `:l1` | Approve agent key for trading |
| `ApproveBuilderFee` | `:l1` | Approve builder fee |

## Vault Operations

| Module | Signing | Description |
|--------|---------|-------------|
| `CreateVault` | `:l1` | Create a new vault |
| `VaultTransfer` | `:l1` | Vault deposits/withdrawals |

## HIP-3 / HIP-4 Deployer Actions

| Module | Description |
|--------|-------------|
| `PerpDeploy` | HIP-3 perp dex deployment and configuration |
| `SpotDeploy` | HIP-1/2 spot token and pair deployment |
| `OutcomeDeploy` | HIP-4 outcome market deployment (see the [HIP-4 guide](../guides/hip-4-outcome-markets.md)) |
| `ActivateOutcomeDeployer` | Activate/deactivate as an outcome deployer |
| `UserOutcome` | Split / merge / negate outcome tokens |

> **Deployer fee ambiguity.** `PerpDeploy` ships both shapes:
> `set_deployer_fees/2` (`setDeployerFees`, the shape in the official docs) and
> `set_fee_scale/3` + `set_growth_modes/2` (`setFeeScale` / `setGrowthModes`,
> the shape `@nktkas/hyperliquid` still emits). Neither is deprecated - which
> one the node accepts has not been confirmed against a live testnet.

> **Deploy actions and signing.** `perpDeploy` and `spotDeploy` are not variants
> of the signer NIF's typed action enum, so they sign through the generic L1
> connection-id path, which hashes the JSON exactly as given. The pre-existing
> deploy variants build their actions from plain Elixir maps, whose key order is
> not pinned, so their on-the-wire hash is not yet verified. See the CHANGELOG's
> "Known issues" section.

## Multi-Sig

Any action above can be wrapped in a `multiSig` action so that a quorum of
authorized signers approves it. See [Multi-Sig Actions](../advanced/multi-sig.md).

## Per-Request Options

```elixir
# Override private key
Order.place_limit("BTC", true, "43000.0", "0.1", private_key: agent_key)

# Vault operations
Order.place_limit("BTC", true, "43000.0", "0.1", vault_address: "0x...")
```

For the complete list of 60 Exchange actions, see the [HexDocs](https://hexdocs.pm/hyperliquid).
