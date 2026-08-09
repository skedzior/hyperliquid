defmodule Hyperliquid.Api.Exchange.UpdateLeverage do
  @moduledoc """
  Update leverage for a perpetual asset.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @doc """
  Update leverage for a perpetual asset.

  ## Parameters
    - `asset`: Asset index
    - `leverage`: New leverage value
    - `is_cross`: true for cross margin, false for isolated
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:vault_address` - Update for a vault

  ## Returns
    - `{:ok, response}` - Update result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = UpdateLeverage.request(0, 10, true)

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  def request(asset, leverage, is_cross, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "updateLeverage",
      asset: asset,
      isCross: is_cross,
      leverage: leverage
    }

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

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
