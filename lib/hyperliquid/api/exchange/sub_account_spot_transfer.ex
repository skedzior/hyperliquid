defmodule Hyperliquid.Api.Exchange.SubAccountSpotTransfer do
  @moduledoc """
  Transfer spot tokens between main account and sub-account.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Utils}
  alias Hyperliquid.Transport.Http

  @doc """
  Transfer spot tokens between main account and sub-account.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `sub_account_user`: Sub-account address
    - `is_deposit`: true for deposit to sub-account, false for withdrawal
    - `token`: Token index
    - `amount`: Amount as string
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` - Transfer result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = SubAccountSpotTransfer.request(private_key, "0x...", true, 1, "100.0")
  """
  def request(sub_account_user, is_deposit, token, amount, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    # IMPORTANT: Use OrderedObject for correct field order in hash calculation
    # Field order: type, subAccountUser, isDeposit, token, amount
    action =
      Jason.OrderedObject.new([
        {:type, "subAccountSpotTransfer"},
        {:subAccountUser, sub_account_user},
        {:isDeposit, is_deposit},
        {:token, token},
        {:amount, Utils.float_to_string(amount)}
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
