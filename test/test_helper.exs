{:ok, _} = Application.ensure_all_started(:bypass)

# Exclude database tests unless the database is configured and available
exclude_tags =
  if Application.get_env(:hyperliquid, :enable_db, false) do
    []
  else
    [:requires_database]
  end

ExUnit.start(exclude: exclude_tags)
