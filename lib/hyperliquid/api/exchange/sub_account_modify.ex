defmodule Hyperliquid.Api.Exchange.SubAccountModify do
  @moduledoc """
  Create or modify a sub-account.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http

  @doc """
  Create or modify a sub-account.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `name`: Sub-account name
    - `opts`: Optional parameters

  ## Options
    - `:sub_account_user` - Sub-account address (for modifying existing)

  ## Returns
    - `{:ok, response}` - Result with sub-account address
    - `{:error, term()}` - Error details

  ## Examples

      # Create new sub-account
      {:ok, result} = SubAccountModify.request(private_key, "Trading Bot")

      # Rename existing sub-account
      {:ok, result} = SubAccountModify.request(private_key, "New Name", sub_account_user: "0x...")
  """
  def request(name, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    sub_account_user = Keyword.get(opts, :sub_account_user)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    # IMPORTANT: Use OrderedObject for correct field order in hash calculation
    # Field order: type, subAccountUser, name
    # Note: subAccountUser is required for modifying existing sub-accounts
    action =
      if sub_account_user do
        Jason.OrderedObject.new([
          {:type, "subAccountModify"},
          {:subAccountUser, sub_account_user},
          {:name, name}
        ])
      else
        # When creating a new sub-account, subAccountUser is not included
        Jason.OrderedObject.new([
          {:type, "subAccountModify"},
          {:name, name}
        ])
      end

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
