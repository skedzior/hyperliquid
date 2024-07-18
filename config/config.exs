import Config

config :hyperliquid,
  is_mainnet: Mix.env() != :test,
  ws_url: "wss://api.hyperliquid.xyz/ws",
  http_url: "https://api.hyperliquid.xyz",
  hl_bridge_contract: "0x2df1c51e09aecf9cacb7bc98cb1742757f163df7",
  private_key: "YOUR_KEY_HERE"

config :hyperliquid, Hyperliquid.Cache.Updater,
  update_interval: :timer.minutes(5)

import_config "#{Mix.env()}.exs"
