defmodule Hyperliquid.Api.Exchange.UsdClassTransfer do
  @moduledoc """
  Transfer USD between spot and perp accounts.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Signer, Utils}
  alias Hyperliquid.Transport.Http

  @doc """
  Transfer USD between spot and perp accounts.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `amount`: Amount to transfer as string
    - `to_perp`: true to transfer to perp, false to transfer to spot
    - `opts`: Optional parameters

  ## Options
    - `:vault_address` - Transfer for a vault

  ## Returns
    - `{:ok, response}` - Transfer result
    - `{:error, term()}` - Error details

  ## Examples

      # Transfer to perp
      {:ok, result} = UsdClassTransfer.request(private_key, "100.0", true)

      # Transfer to spot
      {:ok, result} = UsdClassTransfer.request(private_key, "100.0", false)
  """
  def request(amount, to_perp, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "usdClassTransfer",
      amount: Utils.float_to_string(amount),
      toPerp: to_perp
    }

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
