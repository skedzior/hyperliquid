defmodule Hyperliquid.Api.Exchange.CreateVault do
  @moduledoc """
  Create a new vault.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @doc """
  Create a new vault.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `name`: Vault name (min 3 chars)
    - `description`: Vault description (min 10 chars)
    - `initial_usd`: Initial balance in raw units (float * 1e6, min 100 USDC)
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` - Result with vault address
    - `{:error, term()}` - Error details

  ## Examples

      # Create vault with 100 USDC initial balance
      {:ok, result} = CreateVault.request(private_key, "My Vault", "Trading strategy", 100_000_000)
  """
  def request(name, description, initial_usd, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "createVault",
      name: name,
      description: description,
      initialUsd: initial_usd,
      nonce: nonce
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
