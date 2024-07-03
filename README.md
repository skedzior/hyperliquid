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
    {:hyperliquid, "~> 0.1.1"}
  ]
end
```

## Configuration

In `config/config.exs`, add Hyperliquid protocol host params to your config file

```elixir
config :hyperliquid,
  private_key: "YOUR_KEY_HERE"
```

## Usage

### Streaming Data
To start a WebSocket stream:

```elixir
alias Hyperliquid.Streamer.Supervisor

{:ok, _pid} = Supervisor.start_stream([%{type: "allMids"}])
```
### Placing Orders
To place a market buy order:

```elixir
alias Hyperliquid.Orders

Orders.market_buy("BTC", 1.0)
```

To place a limit sell order:

```elixir
Orders.limit_order("ETH", 2.0, false, 3000, "gtc", false)
```

### Closing Positions
To close all positions for an address:
```elixir
Orders.market_close("0x1234...")
```

## License
This project is licensed under the MIT License.

