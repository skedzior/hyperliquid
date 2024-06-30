import Config

config :hyperliquid,
  is_mainnet: Mix.env() != :test,
  ws_url: "wss://api.hyperliquid.xyz/ws",
  http_url: "https://api.hyperliquid.xyz",
  hl_bridge_contract: "0x2df1c51e09aecf9cacb7bc98cb1742757f163df7",
  private_key: "YOUR_KEY_HERE"

import_config "#{Mix.env()}.exs"
