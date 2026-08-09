defmodule Hyperliquid.Api.Exchange.SendToEvmWithData do
  @moduledoc """
  Send tokens from core to EVM with a custom data payload.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @doc """
  Send tokens from core to EVM with a custom data payload.

  ## Parameters
    - `token`: Token identifier
    - `amount`: Amount to send (string)
    - `source_dex`: Source DEX
    - `destination_recipient`: Destination EVM address
    - `destination_chain_id`: Destination chain ID (integer)
    - `gas_limit`: Gas limit (integer)
    - `data`: Hex-encoded calldata
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:expected_address` - Expected checksummed Ethereum address (0x-prefixed).
      When provided, validates that the private key derives to this address,
      preventing accidental use of an agent sub-key for a funds transfer.
    - `:address_encoding` - "hex" (default) or "base58"

  ## Returns
    - `{:ok, response}` - Transfer result
    - `{:error, term()}` - Error details
  """
  def request(
        token,
        amount,
        source_dex,
        destination_recipient,
        destination_chain_id,
        gas_limit,
        data,
        opts \\ []
      ) do
    private_key = KeyUtils.resolve_and_validate!(opts)
    nonce = generate_nonce()
    is_mainnet = Config.mainnet?()
    address_encoding = Keyword.get(opts, :address_encoding, "hex")

    domain = %{
      name: "HyperliquidSignTransaction",
      version: "1",
      chainId: Hyperliquid.Config.signature_chain_id(),
      verifyingContract: "0x0000000000000000000000000000000000000000"
    }

    types = %{
      "HyperliquidTransaction:SendToEvmWithData" => [
        %{name: "hyperliquidChain", type: "string"},
        %{name: "token", type: "string"},
        %{name: "amount", type: "string"},
        %{name: "sourceDex", type: "string"},
        %{name: "destinationRecipient", type: "string"},
        %{name: "addressEncoding", type: "string"},
        %{name: "destinationChainId", type: "uint64"},
        %{name: "gasLimit", type: "uint64"},
        %{name: "data", type: "string"},
        %{name: "nonce", type: "uint64"}
      ]
    }

    message = %{
      hyperliquidChain: if(is_mainnet, do: "Mainnet", else: "Testnet"),
      token: token,
      amount: amount,
      sourceDex: source_dex,
      destinationRecipient: destination_recipient,
      addressEncoding: address_encoding,
      destinationChainId: destination_chain_id,
      gasLimit: gas_limit,
      data: data,
      nonce: nonce
    }

    with {:ok, domain_json} <- Jason.encode(domain),
         {:ok, types_json} <- Jason.encode(types),
         {:ok, message_json} <- Jason.encode(message),
         {:ok, signature} <-
           KeyUtils.sign_typed_data(
             private_key,
             domain_json,
             types_json,
             message_json,
             "HyperliquidTransaction:SendToEvmWithData"
           ) do
      action =
        Jason.OrderedObject.new([
          {:type, "sendToEvmWithData"},
          {:signatureChainId, Hyperliquid.Config.signature_chain_id_hex()},
          {:hyperliquidChain, if(is_mainnet, do: "Mainnet", else: "Testnet")},
          {:token, token},
          {:amount, amount},
          {:sourceDex, source_dex},
          {:destinationRecipient, destination_recipient},
          {:addressEncoding, address_encoding},
          {:destinationChainId, destination_chain_id},
          {:gasLimit, gas_limit},
          {:data, data},
          {:nonce, nonce}
        ])

      Http.user_signed_request(action, signature, nonce, opts)
    end
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
