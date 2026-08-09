defmodule Hyperliquid.Application do
  @moduledoc false

  use Application

  import Cachex.Spec

  alias Hyperliquid.Config

  @cache :hyperliquid

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
         ]}
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
