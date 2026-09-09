defmodule Hyperliquid.Api.Exchange.SubAccountTransfer do
  @moduledoc """
  Transfer funds between main account and sub-account.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http

  @doc """
  Transfer funds between main account and sub-account.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `sub_account_user`: Sub-account address
    - `is_deposit`: true for deposit to sub-account, false for withdrawal
    - `usd`: Amount in USD as integer (raw value)
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` - Transfer result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = SubAccountTransfer.request(private_key, "0x...", true, 1000000)
  """
  def request(sub_account_user, is_deposit, usd, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    # IMPORTANT: Use OrderedObject for correct field order in hash calculation
    # Field order: type, subAccountUser, isDeposit, usd
    action =
      Jason.OrderedObject.new([
        {:type, "subAccountTransfer"},
        {:subAccountUser, sub_account_user},
        {:isDeposit, is_deposit},
        {:usd, usd}
      ])

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
