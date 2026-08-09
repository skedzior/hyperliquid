defmodule Hyperliquid.Api.Exchange.PerpDeploy do
  @moduledoc """
  Deploy and manage HIP-3 perpetual contracts.

  Sub-action functions:

  | Function                    | SDK key                 | Purpose                                        |
  |-----------------------------|-------------------------|------------------------------------------------|
  | `register_asset2/2`         | `registerAsset2`        | Register a new perp (v2, margin-mode aware)    |
  | `register_asset/2`          | `registerAsset`         | Register a new perp (v1, isolated flag)        |
  | `set_oracle/2`              | `setOracle`             | Update oracle / mark prices for a DEX          |
  | `set_funding_multipliers/2` | `setFundingMultipliers` | Set per-asset funding multipliers              |
  | `halt_trading/3`            | `haltTrading`           | Halt or resume trading for an asset            |
  | `set_margin_table_ids/2`    | `setMarginTableIds`     | Update margin table IDs per asset              |
  | `set_fee_recipient/3`       | `setFeeRecipient`       | Set fee recipient address for a DEX            |
  | `set_open_interest_caps/2`  | `setOpenInterestCaps`   | Set OI cap notionals per asset                 |
  | `set_sub_deployers/3`       | `setSubDeployers`       | Modify sub-deployer permissions                |
  | `set_margin_modes/2`        | `setMarginModes`        | Set margin mode per asset                      |
  | `set_fee_scale/3`           | `setFeeScale`           | Set fee scale (0.0–3.0) for a DEX             |
  | `set_growth_modes/2`        | `setGrowthModes`        | Enable/disable growth mode per asset           |

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/hip-3-deployer-actions

  ## Usage

      # Register a new perp (v2)
      {:ok, _} = PerpDeploy.register_asset2(%{
        max_gas: nil,
        asset_request: %{
          coin: "MYTOKEN",
          sz_decimals: 2,
          oracle_px: "1.5",
          margin_table_id: 1,
          margin_mode: "strictIsolated"
        },
        dex: "my_dex",
        schema: nil
      })

      # Halt trading for an asset
      {:ok, _} = PerpDeploy.halt_trading("MYTOKEN", true)

      # Set fee scale
      {:ok, _} = PerpDeploy.set_fee_scale("my_dex", "1.5")
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @doc """
  Register a new perpetual asset (v2) with margin mode.

  ## Parameters
    - `params`: Map with:
      - `:max_gas`       — Max gas in native token wei, or `nil` to use auction price
      - `:asset_request` — Map with `:coin`, `:sz_decimals`, `:oracle_px`, `:margin_table_id`,
                           `:margin_mode` (`"strictIsolated"` or `"noCross"`)
      - `:dex`           — DEX name string
      - `:schema`        — `nil` or map with `:full_name`, `:collateral_token`, `:oracle_updater`
    - `opts`: Optional keyword list (`:private_key`)
  """
  def register_asset2(params, opts \\ []) do
    ar = Map.fetch!(params, :asset_request)

    action = %{
      type: "perpDeploy",
      registerAsset2: %{
        maxGas: Map.fetch!(params, :max_gas),
        assetRequest: %{
          coin: Map.fetch!(ar, :coin),
          szDecimals: Map.fetch!(ar, :sz_decimals),
          oraclePx: Map.fetch!(ar, :oracle_px),
          marginTableId: Map.fetch!(ar, :margin_table_id),
          marginMode: Map.fetch!(ar, :margin_mode)
        },
        dex: Map.fetch!(params, :dex),
        schema: build_schema(Map.get(params, :schema))
      }
    }

    send_action(action, opts)
  end

  @doc """
  Register a new perpetual asset (v1) with isolated margin flag.

  ## Parameters
    - `params`: Map with:
      - `:max_gas`       — Max gas in native token wei, or `nil`
      - `:asset_request` — Map with `:coin`, `:sz_decimals`, `:oracle_px`,
                           `:margin_table_id`, `:only_isolated` (bool)
      - `:dex`           — DEX name string
      - `:schema`        — `nil` or map with `:full_name`, `:collateral_token`, `:oracle_updater`
    - `opts`: Optional keyword list (`:private_key`)
  """
  def register_asset(params, opts \\ []) do
    ar = Map.fetch!(params, :asset_request)

    action = %{
      type: "perpDeploy",
      registerAsset: %{
        maxGas: Map.fetch!(params, :max_gas),
        assetRequest: %{
          coin: Map.fetch!(ar, :coin),
          szDecimals: Map.fetch!(ar, :sz_decimals),
          oraclePx: Map.fetch!(ar, :oracle_px),
          marginTableId: Map.fetch!(ar, :margin_table_id),
          onlyIsolated: Map.fetch!(ar, :only_isolated)
        },
        dex: Map.fetch!(params, :dex),
        schema: build_schema(Map.get(params, :schema))
      }
    }

    send_action(action, opts)
  end

  @doc """
  Set oracle and mark prices for a DEX.

  ## Parameters
    - `dex`: DEX name string
    - `params`: Map with:
      - `:oracle_pxs`        — `[{coin, price}]` sorted by coin
      - `:mark_pxs`          — `[[{coin, price}]]` list of lists sorted by coin
      - `:external_perp_pxs` — `[{coin, price}]` sorted by coin
    - `opts`: Optional keyword list (`:private_key`)
  """
  def set_oracle(dex, params, opts \\ []) do
    action = %{
      type: "perpDeploy",
      setOracle: %{
        dex: dex,
        oraclePxs: Map.fetch!(params, :oracle_pxs),
        markPxs: Map.fetch!(params, :mark_pxs),
        externalPerpPxs: Map.fetch!(params, :external_perp_pxs)
      }
    }

    send_action(action, opts)
  end

  @doc """
  Set funding multipliers for assets.

  ## Parameters
    - `multipliers`: List of `{coin, multiplier_string}` tuples, sorted by coin
    - `opts`: Optional keyword list (`:private_key`)
  """
  def set_funding_multipliers(multipliers, opts \\ []) when is_list(multipliers) do
    action = %{type: "perpDeploy", setFundingMultipliers: multipliers}
    send_action(action, opts)
  end

  @doc """
  Halt or resume trading for an asset.

  ## Parameters
    - `coin`: Asset coin symbol string
    - `is_halted`: `true` to halt, `false` to resume
    - `opts`: Optional keyword list (`:private_key`)
  """
  def halt_trading(coin, is_halted, opts \\ []) when is_boolean(is_halted) do
    action = %{
      type: "perpDeploy",
      haltTrading: %{coin: coin, isHalted: is_halted}
    }

    send_action(action, opts)
  end

  @doc """
  Update margin table IDs for assets.

  ## Parameters
    - `table_ids`: List of `{coin, table_id_integer}` tuples, sorted by coin
    - `opts`: Optional keyword list (`:private_key`)
  """
  def set_margin_table_ids(table_ids, opts \\ []) when is_list(table_ids) do
    action = %{type: "perpDeploy", setMarginTableIds: table_ids}
    send_action(action, opts)
  end

  @doc """
  Set the fee recipient address for a DEX.

  ## Parameters
    - `dex`: DEX name string
    - `fee_recipient`: Ethereum address string (`"0x..."`)
    - `opts`: Optional keyword list (`:private_key`)
  """
  def set_fee_recipient(dex, fee_recipient, opts \\ []) do
    action = %{
      type: "perpDeploy",
      setFeeRecipient: %{dex: dex, feeRecipient: fee_recipient}
    }

    send_action(action, opts)
  end

  @doc """
  Set open interest cap notionals for assets.

  ## Parameters
    - `caps`: List of `{coin, cap_integer}` tuples, sorted by coin
    - `opts`: Optional keyword list (`:private_key`)
  """
  def set_open_interest_caps(caps, opts \\ []) when is_list(caps) do
    action = %{type: "perpDeploy", setOpenInterestCaps: caps}
    send_action(action, opts)
  end

  @doc """
  Modify sub-deployer permissions for a DEX.

  ## Parameters
    - `dex`: DEX name string
    - `sub_deployers`: List of maps with `:variant`, `:user` (address), `:allowed` (bool)
    - `opts`: Optional keyword list (`:private_key`)
  """
  def set_sub_deployers(dex, sub_deployers, opts \\ []) when is_list(sub_deployers) do
    action = %{
      type: "perpDeploy",
      setSubDeployers: %{
        dex: dex,
        subDeployers:
          Enum.map(sub_deployers, fn sd ->
            %{
              variant: Map.fetch!(sd, :variant),
              user: Map.fetch!(sd, :user),
              allowed: Map.fetch!(sd, :allowed)
            }
          end)
      }
    }

    send_action(action, opts)
  end

  @doc """
  Set margin modes for assets.

  ## Parameters
    - `modes`: List of `{coin, mode_string}` tuples; mode is `"strictIsolated"` or `"noCross"`
    - `opts`: Optional keyword list (`:private_key`)
  """
  def set_margin_modes(modes, opts \\ []) when is_list(modes) do
    action = %{type: "perpDeploy", setMarginModes: modes}
    send_action(action, opts)
  end

  @doc """
  Set the fee scale for a DEX (range 0.0–3.0).

  ## Parameters
    - `dex`: DEX name string
    - `scale`: Fee scale as a decimal string, e.g. `"1.5"`
    - `opts`: Optional keyword list (`:private_key`)
  """
  def set_fee_scale(dex, scale, opts \\ []) do
    action = %{
      type: "perpDeploy",
      setFeeScale: %{dex: dex, scale: scale}
    }

    send_action(action, opts)
  end

  @doc """
  Enable or disable growth mode for assets.

  ## Parameters
    - `modes`: List of `{coin, enabled_bool}` tuples, sorted by coin
    - `opts`: Optional keyword list (`:private_key`)
  """
  def set_growth_modes(modes, opts \\ []) when is_list(modes) do
    action = %{type: "perpDeploy", setGrowthModes: modes}
    send_action(action, opts)
  end

  # ===================== Helpers =====================

  defp build_schema(nil), do: nil

  defp build_schema(schema) do
    %{
      fullName: Map.fetch!(schema, :full_name),
      collateralToken: Map.fetch!(schema, :collateral_token),
      oracleUpdater: Map.get(schema, :oracle_updater)
    }
  end

  defp send_action(action, opts) do
    private_key = KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after) do
      Http.exchange_request(action, signature, nonce, vault_address, expires_after, opts)
    end
  end

  defp sign_action(private_key, action_json, nonce, vault_address, expires_after) do
    is_mainnet = Config.mainnet?()

    case Signer.sign_exchange_action_ex(
           private_key,
           action_json,
           nonce,
           is_mainnet,
           vault_address,
           expires_after
         ) do
      %{"r" => r, "s" => s, "v" => v} ->
        {:ok, %{r: r, s: s, v: v}}

      error ->
        {:error, {:signing_error, error}}
    end
  end

  defp generate_nonce, do: System.system_time(:millisecond)
end
