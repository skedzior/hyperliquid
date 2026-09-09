defmodule Hyperliquid.Api.Exchange.VaultTransfer do
  @moduledoc """
  Transfer funds to/from a vault.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http

  @doc """
  Transfer funds to/from a vault.

  ## Parameters
    - `vault_address`: Vault address
    - `is_deposit`: true for deposit, false for withdrawal
    - `usd`: Amount in **micro-USD as an unsigned integer** (`float * 1e6`),
      matching `@nktkas/hyperliquid` and `hyperliquid-python-sdk`. A string or
      float is rejected on the wire with
      `Failed to deserialize the JSON body into the target type`.
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` - Transfer result
    - `{:error, term()}` - Error details

  ## Examples

      # Deposit 1000 USDC to a vault
      {:ok, result} = VaultTransfer.request("0x...", true, 1_000 * 1_000_000)

      # Withdraw 500 USDC from a vault
      {:ok, result} = VaultTransfer.request("0x...", false, 500 * 1_000_000)
  """
  def request(vault_address, is_deposit, usd, opts \\ []) when is_integer(usd) and usd >= 0 do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "vaultTransfer",
      vaultAddress: vault_address,
      isDeposit: is_deposit,
      usd: usd
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
