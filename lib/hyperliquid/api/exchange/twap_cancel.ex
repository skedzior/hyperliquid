defmodule Hyperliquid.Api.Exchange.TwapCancel do
  @moduledoc """
  Cancel a TWAP order.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @doc """
  Cancel a TWAP order.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `asset`: Asset index
    - `twap_id`: TWAP order ID to cancel
    - `opts`: Optional parameters

  ## Options
    - `:vault_address` - Cancel for a vault

  ## Returns
    - `{:ok, response}` - Cancel result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = TwapCancel.request(private_key, 0, 12345)
  """
  def request(asset, twap_id, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    # IMPORTANT: Use OrderedObject for correct field order in hash calculation
    # Field order: type, a, t
    action =
      Jason.OrderedObject.new([
        {:type, "twapCancel"},
        {:a, asset},
        {:t, twap_id}
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
