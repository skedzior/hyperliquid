# Using Livebook

## Basic Setup

```elixir
Mix.install([
  {:hyperliquid, "~> 0.5"}
],
config: [
  hyperliquid: [
    private_key: "YOUR_PRIVATE_KEY_HERE"
  ]
])
```

## Testnet

```elixir
Mix.install([
  {:hyperliquid, "~> 0.5"}
],
config: [
  hyperliquid: [
    chain: :testnet,
    private_key: "YOUR_TESTNET_KEY"
  ]
])
```

## Example: Market Overview

```elixir
alias Hyperliquid.Api.Info.{AllMids, Meta}

{:ok, mids} = AllMids.request()
{:ok, meta} = Meta.request()

# Display top assets by mid price
mids
|> Enum.sort_by(fn {_k, v} -> -String.to_float(v) end)
|> Enum.take(10)
```
