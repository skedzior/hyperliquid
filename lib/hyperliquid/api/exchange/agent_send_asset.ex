defmodule Hyperliquid.Api.Exchange.AgentSendAsset do
  @moduledoc """
  Agent-scoped counterpart of `Hyperliquid.Api.Exchange.SendAsset`.

  Transfers tokens between perp DEXs, spot balance, users and/or sub-accounts, signed
  by an **agent (API) wallet** rather than the master key. Unlike `sendAsset` this is an
  **L1 action** — it carries no `signatureChainId` / `hyperliquidChain` and is not
  EIP-712 user-signed.

      {"type":"agentSendAsset","destination":"0x...","sourceDex":"...","destinationDex":"...",
       "token":"...","amount":"...","fromSubAccount":"","nonce":<ms>}

  Note the action carries its own inner `nonce` in addition to the request-level nonce;
  both are set to the same millisecond timestamp here, matching the TS SDK.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @doc """
  Transfer tokens as an agent wallet.

  ## Parameters
    - `destination`: Destination address
    - `source_dex`: Source DEX (`""` for the default USDC perp DEX, `"spot"` for spot)
    - `destination_dex`: Destination DEX
    - `token`: Token identifier (e.g. `"USDC:0xeb62eee3685fc4c43992febcd9e75443"`)
    - `amount`: Amount as a decimal string (not wei)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:from_sub_account` - Source sub-account address (`""` for the main account, default `""`)
    - `:vault_address` - Vault address

  ## Examples

      {:ok, result} = AgentSendAsset.request("0x...", "", "spot", "USDC:0x...", "100.0")
  """
  def request(destination, source_dex, destination_dex, token, amount, opts \\ []) do
    private_key = KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action =
      build_action(
        destination,
        source_dex,
        destination_dex,
        token,
        to_string(amount),
        Keyword.get(opts, :from_sub_account, ""),
        nonce
      )

    action = Hyperliquid.Api.Exchange.Action.ordered(action)

    with {:ok, action_json} <- Jason.encode(action),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after) do
      Http.exchange_request(action, signature, nonce, vault_address, expires_after, opts)
    end
  end

  @doc false
  # Exposed for tests: builds the signed action without performing IO.
  # IMPORTANT: OrderedObject preserves key order for the L1 action hash.
  # Key order: type, destination, sourceDex, destinationDex, token, amount,
  #            fromSubAccount, nonce
  def build_action(
        destination,
        source_dex,
        destination_dex,
        token,
        amount,
        from_sub_account,
        nonce
      ) do
    Jason.OrderedObject.new([
      {:type, "agentSendAsset"},
      {:destination, destination},
      {:sourceDex, source_dex},
      {:destinationDex, destination_dex},
      {:token, token},
      {:amount, amount},
      {:fromSubAccount, from_sub_account},
      {:nonce, nonce}
    ])
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

  defp generate_nonce, do: Hyperliquid.Utils.generate_nonce()
end
