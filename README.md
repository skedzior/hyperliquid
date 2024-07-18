# Hyperliquid

Hyperliquid is an Elixir-based library for interacting with the Hyperliquid decentralized exchange platform. It provides a set of modules and functions to manage WebSocket connections, handle orders, and interact with the Hyperliquid API.

## Features

- Order management (market, limit, and close orders)
- Account operations (transfers, leverage adjustment, etc.)
- Price conversion and formatting
- Caching for efficient data access and improved performance
- Dynamic subscription management
- WebSocket streaming for real-time data

## Installation

Add `hyperliquid` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hyperliquid, "~> 0.1.3"}
  ]
end
```

## Livebook

To use in livebook, add the following to the notebook dependencies and setup section:

```elixir
Mix.install([
    {:hyperliquid, "~> 0.1.3"}
  ],
  config: [
    hyperliquid: [private_key: "YOUR_KEY_HERE"]
  ]
)

# You can override the default ws and http urls to use testnet
Mix.install([
    {:hyperliquid, "~> 0.1.3"}
  ],
  config: [
    hyperliquid: [
      ws_url: "wss://api.hyperliquid-testnet.xyz/ws",
      http_url: "https://api.hyperliquid-testnet.xyz",
      private_key: "YOUR_KEY_HERE"
    ]
  ]
)
```

## Configuration

In `config/config.exs`, add Hyperliquid protocol host params to your config file

```elixir
config :hyperliquid,
  private_key: "YOUR_KEY_HERE"
```

## Usage

### Placing Orders
```elixir
# Place a market sell order
Hyperliquid.Orders.market_sell("ETH", 1)

# Place a market buy order for a sub account (vault address)
Hyperliquid.Orders.market_buy("ETH", 1, "0x123...")
{:ok,
  %{
    "response" => %{
      "data" => %{
        "statuses" => [
          %{"filled" => %{"avgPx" => "128.03", "oid" => 17114311614, "totalSz" => "1.0"}}
        ]
      },
      "type" => "order"
    },
    "status" => "ok"
  }}

# Place a limit sell order
Hyperliquid.Orders.limit_order("BTC", 0.5, false, 50000, "gtc", false)
{:ok,
  %{
    "response" => %{
      "data" => %{"statuses" => [%{"resting" => %{"oid" => 10030901240}}]},
      "type" => "order"
    },
    "status" => "ok"
  }}
```

### Closing Positions
```elixir
# Close list of positions
{:ok, %{"assetPositions" => positions}} = Info.clearinghouse_state("0x123")
Hyperliquid.Orders.market_close(positions)

# Close single position
position = Enum.at(positions, 0)
Hyperliquid.Orders.market_close(position)
{:ok, %{
    "response" => %{
      "data" => %{
        "statuses" => [
          %{"filled" => %{"avgPx" => "148.07", "oid" => 10934427319, "totalSz" => "1.0"}}
        ]
      },
      "type" => "order"
    },
    "status" => "ok"
  }}

# Close all positions for an address
Hyperliquid.Orders.market_close("0x123...")
[
  ok: %{
    "response" => %{
      "data" => %{
        "statuses" => [
          %{"filled" => %{"avgPx" => "148.07", "oid" => 10934427319, "totalSz" => "1.0"}}
        ]
      },
      "type" => "order"
    },
    "status" => "ok"
  }
]
```
### Streaming Data
To start a WebSocket stream:

```elixir
# Pass in a single sub or list of subs to start a new ws connection.
{:ok, PID<0.408.0>} = Hyperliquid.Manager.maybe_start_stream(%{type: "allMids"})
{:ok, PID<0.408.0>} = Hyperliquid.Manager.maybe_start_stream([sub_list])
# The manager will check if the sub is currently already subscribed, and if not, open the connection.

# To subscribe to a user address, we call auto_start_user
{:ok, PID<0.408.0>} = Hyperliquid.Manager.auto_start_user(user_address)

# Because we are limited to 10 unique user subscriptions, it is crucial to keep track of which users
# are currently subbed to and that logic is handled internally by the manager but also available to be called externally.
Hyperliquid.Manager.get_subbed_users()
["0x123..."]

Hyperliquid.Manager.get_active_non_user_subs()
[%{type: "allMids"}]

Hyperliquid.Manager.get_active_user_subs()
[
  %{type: "userFundings", user: "0x123..."},
  %{type: "userHistoricalOrders", user: "0x123..."},
  %{type: "userTwapHistory", user: "0x123..."},
  %{type: "userTwapSliceFills", user: "0x123..."},
  %{type: "userNonFundingLedgerUpdates", user: "0x123..."},
  %{type: "userFills", user: "0x123...", aggregateByTime: false},
  %{type: "notification", user: "0x123..."}
]

Manager.get_workers()
[PID<0.633.0>, PID<0.692.0>]
```

Once a Manager has started, it will automatically subscribe to allMids and update the cache. 
The Stream module is broadcasting each event it receives to the "ws_event" channel, 
to subscribe to these events in your own application, simply call subscribe like so:
```elixir
Phoenix.PubSub.subscribe(Hyperliquid.PubSub, channel)
# also available is the shart hand method, via the Utils module.
Hyperliquid.Utils.subscribe(channel)
```

### Cache
The application uses Cachex to handle in memory kv storage for fast and efficient lookup of values 
we frequently need to place valid orders, one of those key items is the current mid price of each asset.

When initialized, the Manager will make several requests to get this data, as well as subscribe to the "allMids" channel. 
This ensures the latest mid price is always up to date and can be immediately accessable.

Quick access utility functions.
```elixir
def meta,         do: Cache.get(:meta)
def spot_meta,    do: Cache.get(:spot_meta)
def all_mids,     do: Cache.get(:all_mids)
def asset_map,    do: Cache.get(:asset_map)
def decimal_map,  do: Cache.get(:decimal_map)
def perps,        do: Cache.get(:perps)
def spot_pairs,   do: Cache.get(:spot_pairs)
def tokens,       do: Cache.get(:tokens)
def ctxs,         do: Cache.get(:ctxs)
def spot_ctxs,    do: Cache.get(:spot_ctxs)
```
You may also note some commonly used util methods in the Cache which can be used like this:

```elixir
Hyperliquid.Cache.asset_from_coin("SOL")
5

Hyperliquid.Cache.decimals_from_coin("SOL")
2

Hyperliquid.Cache.get_token_by_name("HFUN")
%{
  "evmContract" => nil,
  "fullName" => nil,
  "index" => 2,
  "isCanonical" => false,
  "name" => "HFUN",
  "szDecimals" => 2,
  "tokenId" => "0xbaf265ef389da684513d98d68edf4eae",
  "weiDecimals" => 8
}

Hyperliquid.Cache.get_token_by_address("0xbaf265ef389da684513d98d68edf4eae")
%{
  "evmContract" => nil,
  "fullName" => nil,
  "index" => 2,
  "isCanonical" => false,
  "name" => "HFUN",
  "szDecimals" => 2,
  "tokenId" => "0xbaf265ef389da684513d98d68edf4eae",
  "weiDecimals" => 8
}

Hyperliquid.Cache.get_token_key("PURR")
"PURR:0xc1fb593aeffbeb02f85e0308e9956a90"

Hyperliquid.Cache.get_token_by_name("PURR") |> Cache.get_token_key()
"PURR:0xc1fb593aeffbeb02f85e0308e9956a90"

Hyperliquid.Cache.get(:tokens)
[
  %{
    "evmContract" => nil,
    "fullName" => nil,
    "index" => 0,
    "isCanonical" => true,
    "name" => "USDC",
    "szDecimals" => 8,
    "tokenId" => "0x6d1e7cde53ba9467b783cb7c530ce054",
    "weiDecimals" => 8
  },
  ...
]
```
One great place to look for more insight on how to utilize the cache, is the Orders module.

## License
This project is licensed under the MIT License.

