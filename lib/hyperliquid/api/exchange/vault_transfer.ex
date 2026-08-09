defmodule Hyperliquid.Api.Exchange.VaultTransfer do
  @moduledoc """
  Transfer funds to/from a vault.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Signer, Utils}
  alias Hyperliquid.Transport.Http

  @doc """
  Transfer funds to/from a vault.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `vault_address`: Vault address
    - `is_deposit`: true for deposit, false for withdrawal
    - `usd`: Amount in USD as string
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` - Transfer result
    - `{:error, term()}` - Error details

  ## Examples

      # Deposit to vault
      {:ok, result} = VaultTransfer.request(private_key, "0x...", true, "1000.0")

      # Withdraw from vault
      {:ok, result} = VaultTransfer.request(private_key, "0x...", false, "500.0")
  """
  def request(vault_address, is_deposit, usd, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "vaultTransfer",
      vaultAddress: vault_address,
      isDeposit: is_deposit,
      usd: Utils.float_to_string(usd)
    }

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <- sign_action(private_key, action_json, nonce, nil, expires_after) do
      Http.exchange_request(action, signature, nonce, nil, expires_after, opts)
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
