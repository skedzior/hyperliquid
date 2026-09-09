# Subscription API

The Subscription API provides real-time WebSocket data feeds. All modules are under `Hyperliquid.Api.Subscription.*`.

## Connection Types

Each subscription uses one of three connection strategies:

| Type | Behavior | Example |
|------|----------|---------|
| `:shared` | Multiple subscriptions share one connection | AllMids, Trades |
| `:dedicated` | Each subscription gets its own connection | L2Book |
| `:user_grouped` | All subs for the same user share one connection | UserFills, OrderUpdates |

## Market Subscriptions

| Module | Connection | Parameters | Description |
|--------|-----------|-----------|-------------|
| `AllMids` | shared | `dex` (optional) | All mid prices |
| `FastAssetCtxs` | shared | - | Compressed mark/mid prices for all assets |
| `Trades` | shared | `coin` | Recent trades |
| `L2Book` | dedicated | `coin` | Order book updates |
| `Candle` | shared | `coin, interval` | Real-time candles |

## User Subscriptions

| Module | Connection | Parameters | Description |
|--------|-----------|-----------|-------------|
| `UserFills` | user_grouped | `user` | Trade fills |
| `UserFundings` | user_grouped | `user` | Funding payments |
| `OrderUpdates` | user_grouped | `user` | Order status changes |
| `Notification` | user_grouped | `user` | Notifications |
| `UserNonFundingLedgerUpdates` | user_grouped | `user` | Non-funding ledger updates |
| `UserTwapHistory` | user_grouped | `user` | TWAP order history |
| `UserTwapSliceFills` | user_grouped | `user` | TWAP slice fills |

## Explorer Subscriptions

| Module | Connection | Description |
|--------|-----------|-------------|
| `ExplorerBlock` | shared | New blocks |
| `ExplorerTxs` | shared | Transactions |

## Outcome Market Subscriptions

| Module | Connection | Parameters | Description |
|--------|-----------|-----------|-------------|
| `OutcomeMetaUpdates` | shared | - | HIP-4 outcome market metadata updates |

## Optional `dex` Parameter

`AllMids`, `ClearinghouseState`, `OpenOrders` and `TwapStates` take `dex` as an
**optional** parameter defaulting to `""` (the main dex). It used to be
required on the latter three; the widening is backwards compatible.

## Deprecated Channels

`WebData2` is retained but the `webData2` **WebSocket channel** was removed
upstream. Use `WebData3`. The **info** `webData2` method
(`Hyperliquid.Api.Info.WebData2`) is unaffected.

## Compressed Payloads: `fastAssetCtxs`

`FastAssetCtxs` does not carry plain JSON. Its `"data"` is a **base64 string of
raw DEFLATE** (RFC 1951 - no zlib or gzip header, i.e. `inflateInit2(z, -15)`)
wrapping the JSON payload. The subscription module declares a `preprocess/1`
hook and the WebSocket manager decodes it before storage and callbacks, so
subscribers receive decoded data.

The first message is a **full snapshot**; every later message is a **delta** and
must be merged into the accumulated state rather than replacing it:

```elixir
alias Hyperliquid.Api.Subscription.FastAssetCtxs

{:ok, _sub_id} =
  Manager.subscribe(FastAssetCtxs, %{}, fn %{"data" => data} ->
    state = FastAssetCtxs.merge(state, data)
  end)
```

## The `preprocess/1` Hook

A subscription module may define `preprocess/1`. When present, the manager
applies it to the `"data"` half of each event before storage and before any
callback runs. It executes inline on the manager process, so events stay in
arrival order - keep it cheap.

## Usage

```elixir
alias Hyperliquid.WebSocket.Manager

# Subscribe
{:ok, sub_id} = Manager.subscribe(Trades, %{coin: "BTC"})

# Subscribe with callback
{:ok, sub_id} = Manager.subscribe(Trades, %{coin: "BTC"}, fn event ->
  IO.inspect(event)
end)

# List subscriptions
Manager.list_subscriptions()

# Get metrics
{:ok, metrics} = Manager.get_metrics(sub_id)

# Unsubscribe
Manager.unsubscribe(sub_id)
```

## PubSub Integration

All events are broadcast via Phoenix PubSub:

```elixir
Phoenix.PubSub.subscribe(Hyperliquid.PubSub, "ws_event")

def handle_info({:ws_event, event}, state) do
  # Process event
  {:noreply, state}
end
```

For the complete list of 31 subscription channels, see the [HexDocs](https://hexdocs.pm/hyperliquid).
