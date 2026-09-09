defmodule Hyperliquid.Api.Exchange.CSignerAction do
  @moduledoc """
  Perform a validator signer action (unjail).

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http

  @doc """
  Unjail a validator.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` - Action result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = CSignerAction.unjail(private_key)
  """
  def unjail(opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "cSignerAction",
      unjailSelf: true
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
