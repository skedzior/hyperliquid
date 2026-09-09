{:ok, _} = Application.ensure_all_started(:bypass)

# `mix test` must be runnable offline, with no Postgres and no network.
#
# Both exclusions are UNCONDITIONAL — they do not consult `:enable_db`, which
# is set to `true` in config/config.exs and therefore used to make the
# `:requires_database` exclusion inert. Opt back in explicitly:
#
#     HYPERLIQUID_TEST_DB=1 mix test          # include :requires_database
#     HYPERLIQUID_TEST_NETWORK=1 mix test     # include :network
#
# `mix test` (via the `test:` alias in mix.exs) only runs ecto.create/migrate
# when HYPERLIQUID_TEST_DB=1 as well, so the two stay in step.
enabled? = fn var -> System.get_env(var) == "1" end

exclude_tags =
  []
  |> then(fn tags ->
    if enabled?.("HYPERLIQUID_TEST_DB"), do: tags, else: [:requires_database | tags]
  end)
  |> then(fn tags ->
    if enabled?.("HYPERLIQUID_TEST_NETWORK"), do: tags, else: [:network | tags]
  end)

ExUnit.start(exclude: exclude_tags)
