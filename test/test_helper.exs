{:ok, _} = Application.ensure_all_started(:bypass)

# Exclude database tests unless the database is configured and available
exclude_tags =
  if Application.get_env(:hyperliquid, :enable_db, false) do
    []
  else
    [:requires_database]
  end

# Exclude tests that need NIF changes not present in the published precompiled
# artifact. Run them with HYPERLIQUID_BUILD_NIF=1, which builds from source.
exclude_tags =
  if System.get_env("HYPERLIQUID_BUILD_NIF") in ["1", "true"] do
    exclude_tags
  else
    [:requires_native_build | exclude_tags]
  end

ExUnit.start(exclude: exclude_tags)
