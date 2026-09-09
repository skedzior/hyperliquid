defmodule Hyperliquid.Api.Exchange.VaultDistribute do
  @moduledoc """
  Distribute profits to vault followers.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http

  @doc """
  Distribute profits to vault followers.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `vault_address`: Vault address
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` - Distribution result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = VaultDistribute.request(private_key, "0x...")
  """
  def request(vault_address, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "vaultDistribute",
      vaultAddress: vault_address
    }

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <- sign_action(private_key, action_json, nonce, nil, expires_after) do
      Http.exchange_request(action, signature, nonce, nil, expires_after, opts)
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
