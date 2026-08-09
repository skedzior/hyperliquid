defmodule Hyperliquid.Api.Exchange.AgentSendAsset do
  @moduledoc """
  Transfer an asset between DEXs on behalf of a user, signed by an agent wallet.

  The agent-signed counterpart to `Hyperliquid.Api.Exchange.SendAsset`. Because
  it is signed as an L1 action rather than as EIP-712 typed data, an API wallet
  can perform the transfer without the master key.

  Use `""` for the main perps DEX and `"spot"` for the spot account.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint

  ## Usage

      {:ok, result} = AgentSendAsset.request("0xabc...", "", "spot", "USDC", "100")
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @doc """
  Transfer an asset between DEXs.

  ## Parameters
    - `destination`: Destination address
    - `source_dex`: Source DEX (`""` for main perps, `"spot"` for spot)
    - `destination_dex`: Destination DEX
    - `token`: Token name
    - `amount`: Amount as a decimal string
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:from_sub_account` - Sub-account address to send from (default: `""`)
    - `:vault_address` - Act on behalf of a vault

  ## Returns
    - `{:ok, response}` - Transfer result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = AgentSendAsset.request("0xabc...", "", "spot", "USDC", "100")
  """
  @spec request(String.t(), String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def request(destination, source_dex, destination_dex, token, amount, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    from_sub_account = Keyword.get(opts, :from_sub_account, "")
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "agentSendAsset",
      destination: destination,
      sourceDex: source_dex,
      destinationDex: destination_dex,
      token: token,
      amount: amount,
      fromSubAccount: from_sub_account,
      nonce: nonce
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
      %{"r" => r, "s" => s, "v" => v} -> {:ok, %{r: r, s: s, v: v}}
      error -> {:error, {:signing_error, error}}
    end
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
