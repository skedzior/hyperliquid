defmodule Hyperliquid.Config do
  @moduledoc """
  Configuration module for Hyperliquid application.
  """

  @doc """
  Returns the selected chain. Defaults to :mainnet.

  This is controlled by `config :hyperliquid, :chain`.
  """
  def chain do
    Application.get_env(:hyperliquid, :chain, :mainnet)
  end

  @doc """
  Returns the per-chain configuration map for the selected chain.

  Expected structure in your config/config.exs:

      config :hyperliquid,
        chain: :mainnet,
        chains: %{
          mainnet: %{http_url: ..., ws_url: ..., rpc_url: ..., rpc_ws_url: ..., stats_url: ...},
          testnet: %{...}
        }

  Per-key overrides under `:hyperliquid` (e.g. `:http_url`, `:ws_url`) take precedence over this map.
  """
  def chain_cfg do
    chains = Application.get_env(:hyperliquid, :chains, %{})
    Map.get(chains, chain(), %{})
  end

  defp from_env_or_chain(key, default_fun) do
    case Application.get_env(:hyperliquid, key, nil) do
      nil -> Map.get(chain_cfg(), key, default_fun.())
      value -> value
    end
  end

  @doc """
  Returns the base URL of the API.
  """
  def api_base do
    from_env_or_chain(:http_url, fn ->
      if mainnet?(),
        do: "https://api.hyperliquid.xyz",
        else: "https://api.hyperliquid-testnet.xyz"
    end)
  end

  def rpc_base do
    from_env_or_chain(:rpc_url, fn ->
      if mainnet?(),
        do: "https://rpc.hyperliquid.xyz/evm",
        else: "https://rpc.hyperliquid-testnet.xyz/evm"
    end)
  end

  @doc """
  Returns the ws URL of the API.
  """
  def ws_url do
    from_env_or_chain(:ws_url, fn ->
      if mainnet?(),
        do: "wss://api.hyperliquid.xyz/ws",
        else: "wss://api.hyperliquid-testnet.xyz/ws"
    end)
  end

  @doc """
  Returns the explorer (RPC) ws URL of the API.
  """
  def rpc_ws_url do
    from_env_or_chain(:rpc_ws_url, fn ->
      if mainnet?(),
        do: "wss://rpc.hyperliquid.xyz/ws",
        else: "wss://rpc.hyperliquid-testnet.xyz/ws"
    end)
  end

  @doc """
  Returns the explorer HTTP URL.

  Used for block_details, user_details, and tx_details endpoints.
  """
  def explorer_url do
    from_env_or_chain(:explorer_url, fn ->
      if mainnet?(),
        do: "https://rpc.hyperliquid.xyz/explorer",
        else: "https://rpc.hyperliquid-testnet.xyz/explorer"
    end)
  end

  @doc """
  Returns the stats URL of the API.
  """
  def stats_base do
    from_env_or_chain(:stats_url, fn ->
      if mainnet?(),
        do: "https://stats-data.hyperliquid.xyz",
        else: "https://stats-data.hyperliquid-testnet.xyz"
    end)
  end

  @doc """
  Returns whether the application is running on mainnet.
  """
  def mainnet? do
    case Application.get_env(:hyperliquid, :is_mainnet, nil) do
      nil -> chain() == :mainnet
      bool -> bool
    end
  end

  @doc """
  Returns the chain id used in the EIP-712 domain when signing user-signed
  actions, as an integer.

  This value has to appear in two places that must always agree: the `chainId`
  of the EIP-712 domain the signature is produced over, and the
  `signatureChainId` field sent in the action body. The exchange rebuilds the
  domain from `signatureChainId` to recover the signer, so if the two drift the
  API recovers the wrong address and rejects the action. Reading both from here
  is what keeps them in step — they were previously hardcoded in the Rust NIF
  and in a dozen Elixir modules independently.

  The value itself is not constrained by the exchange; any chain id works as
  long as both sides use the same one. The default is `421_614` (`"0x66eee"`,
  Arbitrum Sepolia), matching the official Python SDK and the nktkas TypeScript
  SDK, so signatures produced here are byte-comparable with theirs.

  Override with `config :hyperliquid, signature_chain_id: 42_161`.
  """
  @default_signature_chain_id 421_614

  @spec signature_chain_id() :: non_neg_integer()
  def signature_chain_id do
    Application.get_env(:hyperliquid, :signature_chain_id, @default_signature_chain_id)
  end

  @doc """
  Returns `signature_chain_id/0` as the lowercase hex string used for the
  `signatureChainId` field (e.g. `"0xa4b1"`).
  """
  @spec signature_chain_id_hex() :: String.t()
  def signature_chain_id_hex do
    Hyperliquid.Utils.from_int(signature_chain_id())
  end

  @doc """
  Returns whether debug logging is enabled. Defaults to false.
  Controlled via `config :hyperliquid, debug: true/false` or HL_DEBUG env var.
  """
  def debug? do
    Application.get_env(:hyperliquid, :debug, true) == true
  end

  @doc """
  Returns the private key.
  """
  def secret do
    case Application.get_env(:hyperliquid, :private_key, nil) do
      nil -> Map.get(chain_cfg(), :private_key, nil)
      pk -> pk
    end
  end

  @doc """
  Returns the bridge contract address, used for deposits.
  """
  def bridge_contract do
    from_env_or_chain(:hl_bridge_contract, fn -> "0x2df1c51e09aecf9cacb7bc98cb1742757f163df7" end)
  end

  @doc """
  Optional expiresAfter timestamp in milliseconds. When set, L1 actions will be rejected after this time.
  User-signed actions (e.g., usdSend/spotSend/withdraw3) must not include expiresAfter.
  """
  def expires_after do
    Application.get_env(:hyperliquid, :expires_after, nil)
  end

  @doc """
  Returns the named RPC endpoints configuration.

  Named RPCs allow you to register multiple RPC endpoints and reference them by name.
  This is useful when you want to switch between different RPC providers (e.g., Alchemy, QuickNode, local nodes).

  ## Configuration

  Expected structure in your config/config.exs:

      config :hyperliquid,
        named_rpcs: %{
          alchemy: "https://arb-mainnet.g.alchemy.com/v2/YOUR_KEY",
          quicknode: "https://your-endpoint.quiknode.pro/YOUR_KEY",
          infura: "https://arbitrum-mainnet.infura.io/v3/YOUR_KEY",
          local: "http://localhost:8545",
          backup: "https://rpc-backup.hyperliquid.xyz/evm"
        }

  ## Usage

      # Use a named RPC in your calls
      Hyperliquid.Rpc.Eth.block_number(rpc_name: :alchemy)

      # Or register new ones at runtime
      Hyperliquid.Rpc.Registry.register(:my_node, "https://my-node.xyz")
  """
  def named_rpcs do
    Application.get_env(:hyperliquid, :named_rpcs, %{})
  end

  @doc """
  Returns whether to automatically initialize the cache on application startup.

  When true (default), the cache will be populated with exchange metadata
  and mid prices when the application starts. Set to false to manually
  control cache initialization.

  ## Configuration

      config :hyperliquid,
        autostart_cache: false

  ## Usage

      # Check if cache should autostart
      Hyperliquid.Config.autostart_cache?()
      # => true

      # Disable in config for manual control
      config :hyperliquid, autostart_cache: false
  """
  def autostart_cache? do
    Application.get_env(:hyperliquid, :autostart_cache, true)
  end

  @doc """
  Returns whether database persistence is enabled.

  When true, the application will start Hyperliquid.Repo and Hyperliquid.Storage.Writer,
  enabling Postgres persistence for API data. When false (default), only Cachex storage
  is available.

  ## Configuration

      config :hyperliquid,
        enable_db: true

  ## Required Dependencies

  When enabling database features, ensure these dependencies are available:
  - phoenix_ecto
  - ecto_sql
  - postgrex

  ## Usage

      # Check if database is enabled
      Hyperliquid.Config.db_enabled?()
      # => false

      # Enable in config
      config :hyperliquid, enable_db: true
  """
  def db_enabled? do
    Application.get_env(:hyperliquid, :enable_db, false) == true
  end

  @doc """
  Returns whether Phoenix/LiveView web features are enabled.

  When true, web-specific features like Phoenix controllers and LiveView
  components will be available. This is a future feature flag.

  ## Configuration

      config :hyperliquid,
        enable_web: true

  ## Usage

      # Check if web features are enabled
      Hyperliquid.Config.web_enabled?()
      # => false

      # Enable in config
      config :hyperliquid, enable_web: true
  """
  def web_enabled? do
    Application.get_env(:hyperliquid, :enable_web, false) == true
  end

  @doc """
  Returns the delay in milliseconds between cache initialization retries.

  Defaults to 5000ms (5 seconds). Used by Cache.Warmer when initial
  cache population fails.

  ## Configuration

      config :hyperliquid,
        cache_retry_delay: 10_000

  ## Usage

      Hyperliquid.Config.cache_retry_delay()
      # => 5000
  """
  def cache_retry_delay do
    Application.get_env(:hyperliquid, :cache_retry_delay, 5_000)
  end

  @doc """
  Returns the maximum number of cache initialization retry attempts.

  Defaults to 3 retries. After max retries are exceeded, the application
  continues in degraded mode without cached data.

  ## Configuration

      config :hyperliquid,
        cache_max_retries: 5

  ## Usage

      Hyperliquid.Config.cache_max_retries()
      # => 3
  """
  def cache_max_retries do
    Application.get_env(:hyperliquid, :cache_max_retries, 3)
  end

  @doc """
  Returns the default TTL for cache entries in milliseconds.

  This is the fallback TTL used when no specific TTL is provided.
  Defaults to 300,000ms (5 minutes).

  ## Configuration

      config :hyperliquid,
        cache_default_ttl: 600_000

  ## Usage

      Hyperliquid.Config.cache_default_ttl()
      # => 300_000
  """
  def cache_default_ttl do
    Application.get_env(:hyperliquid, :cache_default_ttl, 300_000)
  end

  @doc """
  Returns the TTL for all_mids cache entries in milliseconds.

  Mid prices change frequently, so this TTL is shorter than the default.
  Defaults to 60,000ms (1 minute).

  ## Configuration

      config :hyperliquid,
        cache_mids_ttl: 30_000

  ## Usage

      Hyperliquid.Config.cache_mids_ttl()
      # => 60_000
  """
  def cache_mids_ttl do
    Application.get_env(:hyperliquid, :cache_mids_ttl, 60_000)
  end

  @doc """
  Returns the TTL for metadata cache entries in milliseconds.

  Metadata (perp_meta, spot_meta) changes less frequently than prices.
  Defaults to 600,000ms (10 minutes).

  ## Configuration

      config :hyperliquid,
        cache_meta_ttl: 900_000

  ## Usage

      Hyperliquid.Config.cache_meta_ttl()
      # => 600_000
  """
  def cache_meta_ttl do
    Application.get_env(:hyperliquid, :cache_meta_ttl, 600_000)
  end

  @doc """
  Returns the maximum number of cache entries before eviction.

  When this limit is reached, LRW (Least Recently Written) eviction
  removes old entries. Defaults to 5000 entries.

  ## Configuration

      config :hyperliquid,
        cache_max_entries: 10_000

  ## Usage

      Hyperliquid.Config.cache_max_entries()
      # => 5000
  """
  def cache_max_entries do
    Application.get_env(:hyperliquid, :cache_max_entries, 5000)
  end

  @doc """
  Returns the fraction of entries to evict when size limit is reached.

  A value of 0.1 means 10% of entries are evicted, creating a buffer
  to prevent constant eviction thrashing. Defaults to 0.1 (10%).

  ## Configuration

      config :hyperliquid,
        cache_reclaim_fraction: 0.15

  ## Usage

      Hyperliquid.Config.cache_reclaim_fraction()
      # => 0.1
  """
  def cache_reclaim_fraction do
    Application.get_env(:hyperliquid, :cache_reclaim_fraction, 0.1)
  end

  @doc """
  Returns the interval for the cache janitor in milliseconds.

  The janitor periodically cleans expired entries. Defaults to 60,000ms (60 seconds).

  ## Configuration

      config :hyperliquid,
        cache_janitor_interval: 120_000

  ## Usage

      Hyperliquid.Config.cache_janitor_interval()
      # => 60_000
  """
  def cache_janitor_interval do
    Application.get_env(:hyperliquid, :cache_janitor_interval, 60_000)
  end
end
