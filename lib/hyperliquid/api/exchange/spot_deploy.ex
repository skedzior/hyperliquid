defmodule Hyperliquid.Api.Exchange.SpotDeploy do
  @moduledoc """
  Deploy and manage HIP-1 and HIP-2 spot tokens.

  Sub-action functions:

  | Function                          | SDK key                      | Purpose                                    |
  |-----------------------------------|------------------------------|--------------------------------------------|
  | `register_token2/2`               | `registerToken2`             | Register a new spot token                  |
  | `user_genesis/2`                  | `userGenesis`                | Set user genesis allocations               |
  | `genesis/2`                       | `genesis`                    | Configure token supply and hyperliquidity  |
  | `register_spot/3`                 | `registerSpot`               | Register a base/quote trading pair         |
  | `register_hyperliquidity/2`       | `registerHyperliquidity`     | Seed liquidity (HIP-2)                     |
  | `set_deployer_trading_fee_share/3`| `setDeployerTradingFeeShare` | Set deployer fee share (0–100%)            |
  | `enable_quote_token/2`            | `enableQuoteToken`           | Convert a token to a quote token           |
  | `enable_aligned_quote_token/2`    | `enableAlignedQuoteToken`    | Enable aligned quote token status          |

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/deploying-hip-1-and-hip-2-assets

  ## Typical deployment sequence

      # 1. Register the token
      {:ok, _} = SpotDeploy.register_token2(%{
        spec: %{name: "MYTOKEN", sz_decimals: 2, wei_decimals: 8},
        max_gas: 1_000_000,
        full_name: "My Token"           # optional
      })

      # 2. Set user genesis allocations (tuples: {address, amount_in_wei})
      {:ok, _} = SpotDeploy.user_genesis(%{
        token: 42,
        user_and_wei: [{"0xabc...", "1000000000"}],
        existing_token_and_wei: []
      })

      # 3. Finalize genesis (max supply)
      {:ok, _} = SpotDeploy.genesis(%{token: 42, max_supply: "1000000000"})

      # 4. Register spot pair (base token, quote token index)
      {:ok, _} = SpotDeploy.register_spot(42, 0)

      # 5. Seed hyperliquidity (HIP-2)
      {:ok, _} = SpotDeploy.register_hyperliquidity(%{
        spot: 10,
        start_px: "1.0",
        order_sz: "100",
        n_orders: 10
      })

      # 6. Set deployer fee share
      {:ok, _} = SpotDeploy.set_deployer_trading_fee_share(42, "50")
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @doc """
  Register a new spot token (HIP-1 step 1).

  ## Parameters
    - `params`: Map with:
      - `:spec`     — `%{name: String, sz_decimals: integer, wei_decimals: integer}`
      - `:max_gas`  — Max gas in native token wei (integer)
      - `:full_name` — Optional full token name string
    - `opts`: Optional keyword list (`:private_key`)
  """
  def register_token2(params, opts \\ []) do
    spec = Map.fetch!(params, :spec)

    action = %{
      type: "spotDeploy",
      registerToken2:
        %{
          spec: %{
            name: Map.fetch!(spec, :name),
            szDecimals: Map.fetch!(spec, :sz_decimals),
            weiDecimals: Map.fetch!(spec, :wei_decimals)
          },
          maxGas: Map.fetch!(params, :max_gas),
          fullName: Map.get(params, :full_name)
        }
        |> drop_nils()
    }

    send_action(action, opts)
  end

  @doc """
  Set user genesis balance allocations for a deployed token (HIP-1 step 2).

  ## Parameters
    - `params`: Map with:
      - `:token`                  — Token integer ID
      - `:user_and_wei`           — List of `{address, amount_wei_string}` tuples
      - `:existing_token_and_wei` — List of `{token_id_integer, amount_wei_string}` tuples
      - `:blacklist_users`        — Optional list of `{address, bool}` tuples
                                    (`true` = blacklist, `false` = remove from blacklist)
    - `opts`: Optional keyword list (`:private_key`)
  """
  def user_genesis(params, opts \\ []) do
    action = %{
      type: "spotDeploy",
      userGenesis:
        %{
          token: Map.fetch!(params, :token),
          userAndWei: Map.fetch!(params, :user_and_wei),
          existingTokenAndWei: Map.fetch!(params, :existing_token_and_wei),
          blacklistUsers: Map.get(params, :blacklist_users)
        }
        |> drop_nils()
    }

    send_action(action, opts)
  end

  @doc """
  Finalize token genesis (max supply and hyperliquidity settings).

  ## Parameters
    - `params`: Map with:
      - `:token`              — Token integer ID
      - `:max_supply`         — Maximum total supply as a decimal string
      - `:no_hyperliquidity`  — Optional; set to `true` to set hyperliquidity balance to 0
    - `opts`: Optional keyword list (`:private_key`)
  """
  def genesis(params, opts \\ []) do
    action = %{
      type: "spotDeploy",
      genesis:
        %{
          token: Map.fetch!(params, :token),
          maxSupply: Map.fetch!(params, :max_supply),
          noHyperliquidity: Map.get(params, :no_hyperliquidity)
        }
        |> drop_nils()
    }

    send_action(action, opts)
  end

  @doc """
  Register a spot trading pair (HIP-1 step 3).

  ## Parameters
    - `base_token`: Base token integer ID
    - `quote_token`: Quote token integer ID (usually 0 for USDC)
    - `opts`: Optional keyword list (`:private_key`)
  """
  def register_spot(base_token, quote_token, opts \\ [])
      when is_integer(base_token) and is_integer(quote_token) do
    action = %{
      type: "spotDeploy",
      registerSpot: %{tokens: [base_token, quote_token]}
    }

    send_action(action, opts)
  end

  @doc """
  Register hyperliquidity seeding configuration for a spot pair (HIP-2).

  ## Parameters
    - `params`: Map with:
      - `:spot`           — Spot index (distinct from base token index)
      - `:start_px`       — Starting price as a decimal string
      - `:order_sz`       — Order size as a decimal string (not in wei)
      - `:n_orders`       — Total number of orders to place (integer)
      - `:n_seeded_levels` — Optional; number of levels to seed with USDC (integer)
    - `opts`: Optional keyword list (`:private_key`)
  """
  def register_hyperliquidity(params, opts \\ []) do
    action = %{
      type: "spotDeploy",
      registerHyperliquidity:
        %{
          spot: Map.fetch!(params, :spot),
          startPx: Map.fetch!(params, :start_px),
          orderSz: Map.fetch!(params, :order_sz),
          nOrders: Map.fetch!(params, :n_orders),
          nSeededLevels: Map.get(params, :n_seeded_levels)
        }
        |> drop_nils()
    }

    send_action(action, opts)
  end

  @doc """
  Set the deployer's trading fee share for a token (0–100%).

  ## Parameters
    - `token`: Token integer ID
    - `share`: Fee share percentage as a decimal string (e.g. `"50"` for 50%)
    - `opts`: Optional keyword list (`:private_key`)
  """
  def set_deployer_trading_fee_share(token, share, opts \\ []) when is_integer(token) do
    action = %{
      type: "spotDeploy",
      setDeployerTradingFeeShare: %{token: token, share: share}
    }

    send_action(action, opts)
  end

  @doc """
  Convert a token to a quote token.

  ## Parameters
    - `token`: Token integer ID to enable as quote token
    - `opts`: Optional keyword list (`:private_key`)
  """
  def enable_quote_token(token, opts \\ []) when is_integer(token) do
    action = %{type: "spotDeploy", enableQuoteToken: %{token: token}}
    send_action(action, opts)
  end

  @doc """
  Enable aligned quote token status for a token.

  ## Parameters
    - `token`: Token integer ID to enable as aligned quote token
    - `opts`: Optional keyword list (`:private_key`)
  """
  def enable_aligned_quote_token(token, opts \\ []) when is_integer(token) do
    action = %{type: "spotDeploy", enableAlignedQuoteToken: %{token: token}}
    send_action(action, opts)
  end

  # ===================== Helpers =====================

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

  defp drop_nils(map) do
    map |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()
  end

  defp generate_nonce, do: System.system_time(:millisecond)
end
