defmodule Hyperliquid.Api.Exchange.CreateSubAccount do
  @moduledoc """
  Create a new sub-account.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http

  @doc """
  Create a new sub-account.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `name`: Sub-account name
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` - Result with sub-account address
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = CreateSubAccount.request(private_key, "Trading Bot")
  """
  def request(name, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    # IMPORTANT: Use OrderedObject for correct field order in hash calculation
    # Field order: type, name
    action =
      Jason.OrderedObject.new([
        {:type, "createSubAccount"},
        {:name, name}
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
