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

# Hyperliquid.Repo is only started when the :requires_database lane is opted
# into with HYPERLIQUID_TEST_DB=1 (see :enable_db above and the `test:` alias
# in mix.exs, which runs ecto.create/ecto.migrate under the same switch).
# Without this block the Repo has no :database key and every :requires_database
# test dies in setup. The defaults match the `postgres` service in
# .github/workflows/ci.yml; the PG* variables are the standard libpq names, so
# a local run against a differently-configured server needs no edits here.
#
# No Ecto.Adapters.SQL.Sandbox: these tests create and drop their own tables
# with raw SQL and share the Writer GenServer, so they need real connections.
if System.get_env("HYPERLIQUID_TEST_DB") == "1" do
  # :ecto_repos is what makes `mix ecto.create` / `mix ecto.migrate` (run by
  # the `test:` alias under the same switch) find the Repo at all. Without it
  # they print "could not find Ecto repos" and silently do nothing, and the
  # suite then fails on a database that was never created.
  config :hyperliquid, ecto_repos: [Hyperliquid.Repo]

  config :hyperliquid, Hyperliquid.Repo,
    username: System.get_env("PGUSER", "postgres"),
    password: System.get_env("PGPASSWORD", "postgres"),
    hostname: System.get_env("PGHOST", "localhost"),
    port: String.to_integer(System.get_env("PGPORT", "5432")),
    database: System.get_env("PGDATABASE", "hyperliquid_test"),
    pool_size: 10
end
