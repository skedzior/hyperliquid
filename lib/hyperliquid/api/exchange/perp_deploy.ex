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
  | `set_deployer_fees/2`       | `setDeployerFees`       | Merged fee scale + growth mode per asset       |
  | `set_perp_annotation/2`     | `setPerpAnnotation`     | Set category/description/keywords metadata     |
  | `disable_dex/2`             | `disableDex`            | Disable a perp DEX                             |

  ## Fee-action name discrepancy (unresolved)

  The official HIP-3 page lists a single **`setDeployerFees`** variant
  (`[[coin, {scale, growthMode}]]`) and lists neither `setFeeScale` nor `setGrowthModes`.
  `@nktkas/hyperliquid` v0.33.3 still emits `setFeeScale` and `setGrowthModes` and has no
  `setDeployerFees`. Since the two references disagree, **all three functions are kept**:
  `set_fee_scale/3` and `set_growth_modes/2` (nktkas shape) and `set_deployer_fees/2`
  (docs shape). Nothing is deprecated until a live testnet deploy settles which the node
  accepts.

  The docs page also lists `setFundingInterestRates` and nktkas additionally has
  `insertMarginTable`; neither is implemented here yet.

  ## `registerAsset2` schema fields

  `schema` accepts exactly `fullName`, `collateralToken`, `oracleUpdater` — verified
  against nktkas v0.33.3. The extra `Hip3Schema` fields in the RE mirror (`feeRecipient`,
  `assetToOiCap`, `subDeployers`, `deployerFeeScale`, `lastDeployerFeeScaleChangeTime`)
  are server-derived and are not accepted on the wire. Note `marginMode` also accepts
  `"normal"` upstream in addition to `"strictIsolated"` / `"noCross"`.

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

  alias Hyperliquid.Config
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

  @doc """
  Set fee scale and growth mode per asset in one action (docs shape).

  Emits `{"type":"perpDeploy","setDeployerFees":[[coin,{"scale":...,"growthMode":...}]]}`.

  See the module doc's "Fee-action name discrepancy" note: the official page documents
  this variant while nktkas still emits the older `setFeeScale` / `setGrowthModes` pair.

  ## Parameters
    - `fees`: List of `{coin, %{scale: scale_string, growth_mode: bool}}` tuples
      (2-element lists also accepted), sorted by coin
    - `opts`: Optional keyword list (`:private_key`)

  ## Examples

      {:ok, _} = PerpDeploy.set_deployer_fees([
        {"MYTOKEN", %{scale: "1.5", growth_mode: true}}
      ])
  """
  def set_deployer_fees(fees, opts \\ []) when is_list(fees) do
    entries =
      Enum.map(fees, fn
        {coin, cfg} -> [coin, build_deployer_fee(cfg)]
        [coin, cfg] -> [coin, build_deployer_fee(cfg)]
      end)

    action = %{type: "perpDeploy", setDeployerFees: entries}
    send_action(action, opts)
  end

  @doc """
  Set the searchable/display annotation for a perp asset.

  ## Parameters
    - `annotation`: Map with:
      - `:coin`         — Asset symbol string
      - `:category`     — Classification label (max 15 characters)
      - `:description`  — Detailed description (max 400 characters)
      - `:display_name` — Display name string, or `nil` to keep the L1 name
      - `:keywords`     — List of keyword strings used as search hints
    - `opts`: Optional keyword list (`:private_key`)

  Note the annotation fields are siblings of `coin` (unlike the spot variant, which
  nests them under an `annotation` object).
  """
  def set_perp_annotation(annotation, opts \\ []) do
    # IMPORTANT: OrderedObject pins the key order the L1 action hash depends on.
    action =
      Jason.OrderedObject.new([
        {:type, "perpDeploy"},
        {:setPerpAnnotation,
         Jason.OrderedObject.new([
           {:coin, Map.fetch!(annotation, :coin)},
           {:category, Map.fetch!(annotation, :category)},
           {:description, Map.fetch!(annotation, :description)},
           {:displayName, Map.get(annotation, :display_name)},
           {:keywords, Map.fetch!(annotation, :keywords)}
         ])}
      ])

    send_action(action, opts)
  end

  @doc """
  Disable a perp DEX.

  Note the payload is a bare string, not an object.

  ## Parameters
    - `dex`: DEX name string
    - `opts`: Optional keyword list (`:private_key`)
  """
  def disable_dex(dex, opts \\ []) when is_binary(dex) do
    action = %{type: "perpDeploy", disableDex: dex}
    send_action(action, opts)
  end

  # ===================== Helpers =====================

  defp build_deployer_fee(cfg) do
    Jason.OrderedObject.new([
      {:scale, Map.fetch!(cfg, :scale)},
      {:growthMode, Map.fetch!(cfg, :growth_mode)}
    ])
  end

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
    Hyperliquid.Api.Exchange.Action.sign_json(
      private_key,
      action_json,
      nonce,
      vault_address,
      expires_after
    )
  end

  defp generate_nonce, do: Hyperliquid.Utils.generate_nonce()
end
