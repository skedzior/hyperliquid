defmodule Hyperliquid.Application do
  @moduledoc false

  use Application

  import Cachex.Spec

  alias Hyperliquid.Config

  @cache :hyperliquid
  @meta_cache :hyperliquid_meta
  @http_pool :hyperliquid_http

  @impl true
  def start(_type, _args) do
    # Validate DB dependencies if enabled
    if Config.db_enabled?() do
      validate_db_dependencies!()
    end

    # Core children that always start
    # Order: PubSub, Cachex, Warmer (needs Cachex), Registry, WebSocket.Supervisor
    core_children =
      [
        {Phoenix.PubSub, name: Hyperliquid.PubSub},
        # Dedicated hackney pool - the SDK must not share (and exhaust)
        # hackney's global :default pool with the host application.
        :hackney_pool.child_spec(@http_pool,
          timeout: 60_000,
          max_connections: Config.http_pool_size()
        ),
        # Exchange metadata lives in its own Cachex instance with NO size
        # limit, so the WS firehose written into :hyperliquid can never evict
        # :asset_map / :decimal_map / :all_mids.
        Supervisor.child_spec({Cachex, name: @meta_cache}, id: @meta_cache),
        # Both Cachex children carry an explicit `id:` — two `{Cachex, ...}`
        # tuples default to the same child id (`Cachex`) and the supervisor
        # refuses to start.
        Supervisor.child_spec(
          {Cachex,
           [
             name: @cache,
             hooks: [
               hook(
                 module: Cachex.Limit.Scheduled,
                 args: {
                   Config.cache_max_entries(),
                   [reclaim: Config.cache_reclaim_fraction()],
                   [frequency: 10_000]
                 }
               )
             ]
           ]},
          id: @cache
        )
      ] ++
        if Config.autostart_cache?() do
          [Hyperliquid.Cache.Warmer]
        else
          []
        end ++
        [
          {Hyperliquid.Rpc.Registry,
           [
             rpcs:
               Config.named_rpcs()
               |> then(fn rpcs ->
                 if Config.node_rpc_enabled?(),
                   do: Map.put(rpcs, :node, "#{Config.node_url()}/evm"),
                   else: rpcs
               end)
           ]},
          Hyperliquid.WebSocket.Supervisor
        ]

    # Database children (only when enable_db: true)
    db_children =
      if Config.db_enabled?() do
        [Hyperliquid.Repo, Hyperliquid.Storage.Writer]
      else
        []
      end

    # Build final children list
    children = core_children ++ db_children

    opts = [strategy: :one_for_one, name: Hyperliquid.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp validate_db_dependencies! do
    required_apps = [:ecto_sql, :postgrex, :phoenix_ecto]

    missing_apps =
      Enum.reject(required_apps, fn app ->
        case Application.load(app) do
          :ok -> true
          {:error, {:already_loaded, _}} -> true
          _ -> false
        end
      end)

    unless Enum.empty?(missing_apps) do
      raise """
      Database features are enabled (enable_db: true) but required dependencies are missing.

      Missing dependencies: #{inspect(missing_apps)}

      Please add to your mix.exs deps:
        {:phoenix_ecto, "~> 4.5"},
        {:ecto_sql, "~> 3.10"},
        {:postgrex, ">= 0.0.0"}

      Then run: mix deps.get

      Or disable database features in your config:
        config :hyperliquid, enable_db: false
      """
    end
  end
end
