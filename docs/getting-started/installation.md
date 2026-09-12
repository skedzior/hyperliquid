# Installation

## Requirements

- Elixir 1.15+
- Erlang/OTP 26+
- Rust toolchain (for the native signing NIF)

## Add Dependency

Add `hyperliquid` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hyperliquid, "~> 0.5"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Optional: Database Support

To enable Postgres persistence, add the database dependencies:

```elixir
def deps do
  [
    {:hyperliquid, "~> 0.5"},
    {:phoenix_ecto, "~> 4.5"},
    {:ecto_sql, "~> 3.10"},
    {:postgrex, ">= 0.0.0"}
  ]
end
```

## Verify Installation

Start an IEx session to confirm everything is working:

```bash
iex -S mix
```

```elixir
iex> Hyperliquid.Api.Info.AllMids.request()
{:ok, %{"BTC" => "43250.5", "ETH" => "2280.75", ...}}
```
