defmodule Hyperliquid.Api.Exchange.SendToEvmWithData do
  @moduledoc """
  Send tokens from core to EVM with a custom data payload.

  `sendToEvmWithData` is a **user-signed** (EIP-712) action, signed under
  `HyperliquidTransaction:SendToEvmWithData`. The signed struct is

      hyperliquidChain      string
      token                 string
      amount                string
      sourceDex             string
      destinationRecipient  string
      addressEncoding       string
      destinationChainId    uint32
      gasLimit              uint64
      data                  bytes
      nonce                 uint64

  matching `@nktkas/hyperliquid` (`SendToEvmWithDataTypes`). Until the 2026-09 API sync this
  module declared `destinationChainId` as `uint64` and `data` as `string`. Both
  the Solidity types and the resulting encoding differ (`bytes` is hashed, a
  `string` of hex text is not), so those signatures could never have been
  recovered to the sending address.

  `data` is hex-encoded calldata (`"0x"` for an empty payload).

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint#send-to-evm-with-data
  """

  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http
  alias Hyperliquid.Utils

  @primary_type "HyperliquidTransaction:SendToEvmWithData"
  @fields [
    {"token", "string"},
    {"amount", "string"},
    {"sourceDex", "string"},
    {"destinationRecipient", "string"},
    {"addressEncoding", "string"},
    {"destinationChainId", "uint32"},
    {"gasLimit", "uint64"},
    {"data", "bytes"},
    {"nonce", "uint64"}
  ]

  @doc """
  Send tokens from core to EVM with a custom data payload.

  ## Parameters
    - `token`: Token identifier
    - `amount`: Amount to send (string)
    - `source_dex`: Source DEX
    - `destination_recipient`: Destination EVM address
    - `destination_chain_id`: Destination chain ID (integer, `uint32`)
    - `gas_limit`: Gas limit (integer)
    - `data`: Hex-encoded calldata (`"0x"` for none)
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
    nonce = Utils.generate_nonce()
    is_mainnet = Config.mainnet?()
    address_encoding = Keyword.get(opts, :address_encoding, "hex")

    with {:ok, signature} <-
           sign(
             private_key,
             token,
             amount,
             source_dex,
             destination_recipient,
             address_encoding,
             destination_chain_id,
             gas_limit,
             data,
             nonce,
             is_mainnet
           ) do
      action =
        build_action(
          token,
          amount,
          source_dex,
          destination_recipient,
          address_encoding,
          destination_chain_id,
          gas_limit,
          data,
          nonce,
          is_mainnet
        )

      Http.user_signed_request(action, signature, nonce, opts)
    end
  end

  @doc """
  The wire action, in the canonical field order
  (`type`, `signatureChainId`, `hyperliquidChain`, then the signed fields).
  """
  def build_action(
        token,
        amount,
        source_dex,
        destination_recipient,
        address_encoding,
        destination_chain_id,
        gas_limit,
        data,
        nonce,
        is_mainnet \\ nil
      ) do
    Jason.OrderedObject.new([
      {:type, "sendToEvmWithData"},
      {:signatureChainId, UserSigned.signature_chain_id()},
      {:hyperliquidChain, UserSigned.hyperliquid_chain(is_mainnet)},
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
  end

  @doc false
  def sign(
        private_key,
        token,
        amount,
        source_dex,
        destination_recipient,
        address_encoding,
        destination_chain_id,
        gas_limit,
        data,
        nonce,
        is_mainnet \\ nil
      ) do
    UserSigned.sign(
      private_key,
      @primary_type,
      @fields,
      [
        {"token", token},
        {"amount", amount},
        {"sourceDex", source_dex},
        {"destinationRecipient", destination_recipient},
        {"addressEncoding", address_encoding},
        {"destinationChainId", destination_chain_id},
        {"gasLimit", gas_limit},
        {"data", data},
        {"nonce", nonce}
      ],
      is_mainnet
    )
  end
end
