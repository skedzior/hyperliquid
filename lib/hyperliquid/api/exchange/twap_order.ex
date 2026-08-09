defmodule Hyperliquid.Api.Exchange.TwapOrder do
  @moduledoc """
  Place a TWAP (Time-Weighted Average Price) order.

  TWAP orders split large orders into smaller chunks executed over time.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Signer, Utils}
  alias Hyperliquid.Transport.Http

  @doc """
  Place a TWAP order.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `asset`: Asset index
    - `is_buy`: true for buy, false for sell
    - `sz`: Total size
    - `opts`: Order options

  ## Options
    - `:reduce_only` - Only reduce position (default: false)
    - `:duration_minutes` - Duration in minutes (default: 5)
    - `:randomize` - Randomize execution (default: false)
    - `:vault_address` - Trade for a vault

  ## Returns
    - `{:ok, response}` - Order result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = TwapOrder.request(private_key, 0, true, "1.0", duration_minutes: 30)
  """
  def request(asset, is_buy, sz, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    # IMPORTANT: Use OrderedObject for correct field order in hash calculation
    # Twap field order: a, b, s, r, m, t
    twap =
      Jason.OrderedObject.new([
        {:a, asset},
        {:b, is_buy},
        {:s, Utils.float_to_string(sz)},
        {:r, Keyword.get(opts, :reduce_only, false)},
        {:m, Keyword.get(opts, :duration_minutes, 5)},
        {:t, Keyword.get(opts, :randomize, false)}
      ])

    # Action field order: type, twap
    action =
      Jason.OrderedObject.new([
        {:type, "twapOrder"},
        {:twap, twap}
      ])

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after) do
      Http.exchange_request(action, signature, nonce, vault_address, expires_after, opts)
    end
  end

  defp sign_action(private_key, action_json, nonce, vault_address, expires_after) do
    is_mainnet = Config.mainnet?()

    connection_id =
      Signer.compute_connection_id_ex(action_json, nonce, vault_address, expires_after)

    case Signer.sign_l1_action(private_key, connection_id, is_mainnet) do
      %{"r" => r, "s" => s, "v" => v} ->
        {:ok, %{r: r, s: s, v: v}}

      error ->
        {:error, {:signing_error, error}}
    end
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
