# Endpoint DSL

The SDK uses macros to generate API endpoint modules from declarative definitions.

## Info / Explorer Endpoints

```elixir
defmodule Hyperliquid.Api.Info.AllMids do
  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "allMids",
    optional_params: [:dex],
    rate_limit_cost: 2,
    raw_response: true,
    doc: "Retrieve mid prices for all actively traded coins"

  embedded_schema do
    field(:mids, :map)
    field(:dex, :string)
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    struct
    |> cast(attrs, [:mids, :dex])
  end
end
```

### DSL Options

| Option | Required | Description |
|--------|----------|-------------|
| `:type` | Yes | `:info`, `:explorer`, or `:stats` |
| `:request_type` | Yes | The `"type"` field value in the request payload |
| `:request` | No | Static request map (for no-param endpoints) |
| `:params` | No | Required parameters (atoms) |
| `:optional_params` | No | Optional parameters |
| `:rate_limit_cost` | No | Rate limit weight (default: 0) |
| `:doc` | No | Documentation string |
| `:returns` | No | Return value description |
| `:raw_response` | No | Generate `request_raw/N` functions |
| `:storage` | No | Storage configuration |

### Generated Functions

- `request/N` / `request!/N` - API call with `{:ok, t()}` / raises
- `build_request/N` - Build request parameters
- `parse_response/1` - Parse and validate response via changeset
- `rate_limit_cost/0` - Rate limit cost
- `__endpoint_info__/0` - Endpoint metadata

With storage enabled, also generates:
- `fetch/N` / `fetch!/N` - Fetch with storage fallback
- `__postgres_tables__/0`, `__storage_config__/0`

## Exchange Endpoints

```elixir
defmodule Hyperliquid.Api.Exchange.Order do
  use Hyperliquid.Api.ExchangeEndpoint,
    action_type: "order",
    signing: :exchange,
    rate_limit_cost: 1

  def build_action(orders, grouping, builder) do
    %{type: "order", orders: orders, grouping: grouping}
  end
end
```

### Exchange DSL Options

| Option | Required | Description |
|--------|----------|-------------|
| `:action_type` | Yes | Exchange action type |
| `:signing` | Yes | `:exchange` or `:l1` |
| `:params` | No | Required parameters |
| `:optional_params` | No | Optional params (default includes `:vault_address`) |
| `:rate_limit_cost` | No | Rate limit weight |

## Subscription Endpoints

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
    end
  end
end
```

### Storage Configuration

```elixir
storage: [
  postgres: [
    enabled: true,
    table: "trades",
    extract: :records,
    conflict_target: :hash,
    on_conflict: {:replace, [:field1, :field2]}
  ],
  cache: [
    enabled: true,
    ttl: :timer.minutes(5),
    key_pattern: "block:{{block_number}}"
  ],
  context_params: [:user]
]
```

## Endpoint Registry

`Hyperliquid.Api.Registry` lists every endpoint module, grouped by context
(`:info`, `:exchange`, `:subscription`, `:explorer`, `:stats`). The list is
exhaustive: `test/api/registry_coverage_test.exs` globs
`lib/hyperliquid/api/<context>/` at test time and fails if a module is missing
or stale.

```elixir
Registry.list_endpoints()                     # every module that exposes metadata
Registry.list_by_type(:subscription)          # all 31 channels
Registry.list_context_endpoints(:exchange)    # all 60 modules, metadata or not
Registry.get_endpoint_info("fastAssetCtxs")
Registry.resolve_endpoint(:info, :all_mids)
```

Metadata comes from one of two callbacks:

| DSL | Callback | Contexts |
|-----|----------|----------|
| `use Hyperliquid.Api.Endpoint` | `__endpoint_info__/0` | info, explorer, stats |
| `use Hyperliquid.Api.SubscriptionEndpoint` | `__subscription_info__/0` | subscription |

`list_endpoints/0` normalises `__subscription_info__/0` into the
`__endpoint_info__/0` shape, so subscriptions appear alongside everything else.

Most `Exchange` modules are hand-written action builders using neither DSL, so
they expose no metadata. They are still registered — `resolve_endpoint/2` and
`list_context_endpoints/1` see them — but they do not appear in
`list_endpoints/0`. Two exceptions (`Noop`, `SetDisplayName`) use
`Hyperliquid.Api.ExchangeEndpoint` and do.

Deliberately unregistered: `Hyperliquid.Api.Exchange.KeyUtils` (a helper) and
`Hyperliquid.Api.MultiSig` (a signing orchestrator, not an endpoint).
