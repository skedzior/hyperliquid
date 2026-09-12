defmodule Hyperliquid.Api.Exchange.UpdateIsolatedMargin do
  @moduledoc """
  Add or remove margin from an isolated position.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http

  @doc """
  Add or remove margin from an isolated position.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `asset`: Asset index
    - `is_buy`: true for long position, false for short
    - `ntli`: Amount to add (positive) or remove (negative)
    - `opts`: Optional parameters

  ## Options
    - `:vault_address` - Update for a vault

  ## Returns
    - `{:ok, response}` - Update result
    - `{:error, term()}` - Error details

  ## Examples

      # Add margin
      {:ok, result} = UpdateIsolatedMargin.request(private_key, 0, true, 100)

      # Remove margin
      {:ok, result} = UpdateIsolatedMargin.request(private_key, 0, true, -50)
  """
  def request(asset, is_buy, ntli, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "updateIsolatedMargin",
      asset: asset,
      isBuy: is_buy,
      ntli: ntli
    }

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

  defp generate_nonce do
    Hyperliquid.Utils.generate_nonce()
  end
end
