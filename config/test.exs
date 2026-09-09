import Config

# The test suite must be hermetic: no network, no Postgres, no background
# cache/WS warmers. Tests that need an HTTP server stand up Bypass and
# override the relevant *_url key themselves.
config :hyperliquid,
  # Sentinel bases: any un-stubbed request fails loudly (ECONNREFUSED on a
  # reserved port) instead of silently reaching the live testnet.
  ws_url: "ws://127.0.0.1:1/ws",
  http_url: "http://127.0.0.1:1",
  hl_bridge_contract: "0x1870dc7a474e045026f9ef053d5bb20a250cc084",
  # Do not start Hyperliquid.Repo / Storage.Writer; :requires_database tests
  # are excluded by default (see test/test_helper.exs). Opt in with
  # HYPERLIQUID_TEST_DB=1, which also flips this back on.
  enable_db: System.get_env("HYPERLIQUID_TEST_DB") == "1",
  # No live HTTP/WS warming from the supervision tree.
  autostart_cache: false

# Build the Rust signer NIF from source in the test env so signing changes in
# native/signer/ are covered by the cross-SDK vector suite.
config :rustler_precompiled, :force_build, hyperliquid: true
