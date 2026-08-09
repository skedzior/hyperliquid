defmodule Hyperliquid.Api.Exchange.SendAsset do
  @moduledoc """
  Transfer tokens between different perp DEXs, spot balance, users, and/or sub-accounts.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint#send-asset
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @doc """
  Transfer tokens between different perp DEXs, spot balance, users, and/or sub-accounts.

  ## Parameters
    - `destination`: Destination address
    - `source_dex`: Source DEX ("" for default USDC perp DEX, "spot" for spot)
    - `destination_dex`: Destination DEX ("" for default USDC perp DEX, "spot" for spot)
    - `token`: Token identifier (e.g., "USDC:0xeb62eee3685fc4c43992febcd9e75443")
    - `amount`: Amount to send as string (not in wei)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:expected_address` - When provided, validates the private key derives to this address
    - `:from_sub_account` - Source sub-account address ("" for main account, default: "")

  ## Returns
    - `{:ok, response}` - Transfer result
    - `{:error, term()}` - Error details

  ## Examples

      # Transfer from perp to spot
      {:ok, result} = SendAsset.request(
        "0x...",
        "",
        "spot",
        "USDC:0xeb62eee3685fc4c43992febcd9e75443",
        "100.0"
      )

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  def request(
        destination,
        source_dex,
        destination_dex,
        token,
        amount,
        opts \\ []
      ) do
    private_key = KeyUtils.resolve_and_validate!(opts)
    time = generate_nonce()
    is_mainnet = Config.mainnet?()
    from_sub_account = Keyword.get(opts, :from_sub_account, "")

    sig =
      sign_send_asset(
        private_key,
        destination,
        source_dex,
        destination_dex,
        token,
        amount,
        from_sub_account,
        time,
        is_mainnet
      )

    # IMPORTANT: Use OrderedObject for correct field order in hash calculation
    # Field order: type, signatureChainId, hyperliquidChain, destination, sourceDex,
    #              destinationDex, token, amount, fromSubAccount, nonce
    action =
      Jason.OrderedObject.new([
        {:type, "sendAsset"},
        {:signatureChainId, Hyperliquid.Config.signature_chain_id_hex()},
        {:hyperliquidChain, if(is_mainnet, do: "Mainnet", else: "Testnet")},
        {:destination, destination},
        {:sourceDex, source_dex},
        {:destinationDex, destination_dex},
        {:token, token},
        {:amount, amount},
        {:fromSubAccount, from_sub_account},
        {:nonce, time}
      ])

    signature = %{r: sig["r"], s: sig["s"], v: sig["v"]}

    Http.user_signed_request(action, signature, time, opts)
  end

  defp sign_send_asset(
         private_key,
         destination,
         source_dex,
         destination_dex,
         token,
         amount,
         from_sub_account,
         nonce,
         is_mainnet
       ) do
    # EIP-712 domain — Hyperliquid uses chainId 42161 (Arbitrum One) for BOTH
    # mainnet and testnet. The domain name must be "HyperliquidSignTransaction".
    domain = %{
      name: "HyperliquidSignTransaction",
      version: "1",
      chainId: Hyperliquid.Config.signature_chain_id(),
      verifyingContract: "0x0000000000000000000000000000000000000000"
    }

    # EIP-712 types for SendAsset
    types = %{
      "EIP712Domain" => [
        %{name: "name", type: "string"},
        %{name: "version", type: "string"},
        %{name: "chainId", type: "uint256"},
        %{name: "verifyingContract", type: "address"}
      ],
      "HyperliquidTransaction:SendAsset" => [
        %{name: "hyperliquidChain", type: "string"},
        %{name: "destination", type: "string"},
        %{name: "sourceDex", type: "string"},
        %{name: "destinationDex", type: "string"},
        %{name: "token", type: "string"},
        %{name: "amount", type: "string"},
        %{name: "fromSubAccount", type: "string"},
        %{name: "nonce", type: "uint64"}
      ]
    }

    # Message to sign
    message = %{
      hyperliquidChain: if(is_mainnet, do: "Mainnet", else: "Testnet"),
      destination: destination,
      sourceDex: source_dex,
      destinationDex: destination_dex,
      token: token,
      amount: amount,
      fromSubAccount: from_sub_account,
      nonce: nonce
    }

    # Convert to JSON for signing
    domain_json = Jason.encode!(domain)
    types_json = Jason.encode!(types)
    message_json = Jason.encode!(message)
    primary_type = "HyperliquidTransaction:SendAsset"

    Signer.sign_typed_data(private_key, domain_json, types_json, message_json, primary_type)
  end

  # Hyperliquid uses signatureChainId 42161 (Arbitrum One) for BOTH mainnet and testnet.
  # The network distinction is conveyed via the hyperliquidChain field ("Mainnet"/"Testnet").

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
