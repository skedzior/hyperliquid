defmodule Hyperliquid.Api.Exchange.TokenDelegate do
  @moduledoc """
  Delegate or undelegate stake to/from a validator.

  `tokenDelegate` is a **user-signed** (EIP-712) action, signed under
  `HyperliquidTransaction:TokenDelegate` with the fields `hyperliquidChain`,
  `validator` (address), `wei`, `isUndelegate`, `nonce`.

  Before v0.2.4 this module built its own typed data with `validator` typed as
  `string` and `isUndelegate` declared *before* `wei`. Both the type and the
  declaration order feed the EIP-712 type hash and the encoded struct, so those
  signatures could never have been recovered to the sending address.
  `@nktkas/hyperliquid` (`TokenDelegateTypes`) and `hyperliquid-python-sdk`
  (`TOKEN_DELEGATE_TYPES`) both use the order below.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint#delegate-or-undelegate-stake-from-validator
  """

  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http
  alias Hyperliquid.Utils

  @primary_type "HyperliquidTransaction:TokenDelegate"
  @fields [
    {"validator", "address"},
    {"wei", "uint64"},
    {"isUndelegate", "bool"},
    {"nonce", "uint64"}
  ]

  @doc """
  Delegate or undelegate stake to/from a validator.

  ## Parameters
    - `validator`: Validator address (0x...)
    - `is_undelegate`: true to undelegate, false to delegate
    - `wei`: Amount in wei (integer)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)

  ## Returns
    - `{:ok, response}` - Delegation result
    - `{:error, term()}` - Error details

  ## Examples

      # Delegate 1 HYPE
      {:ok, result} = TokenDelegate.request("0x...", false, 100_000_000)

      # Undelegate
      {:ok, result} = TokenDelegate.request("0x...", true, 100_000_000)
  """
  def request(validator, is_undelegate, wei, opts \\ []) do
    private_key = KeyUtils.resolve_private_key!(opts)
    validator = String.downcase(validator)
    nonce = Utils.generate_nonce()
    is_mainnet = Config.mainnet?()

    with {:ok, signature} <- sign(private_key, validator, is_undelegate, wei, nonce, is_mainnet) do
      Http.user_signed_request(
        build_action(validator, is_undelegate, wei, nonce, is_mainnet),
        signature,
        nonce,
        opts
      )
    end
  end

  @doc """
  The wire action, in the canonical field order
  (`type`, `signatureChainId`, `hyperliquidChain`, `validator`, `wei`,
  `isUndelegate`, `nonce`).
  """
  def build_action(validator, is_undelegate, wei, nonce, is_mainnet \\ nil) do
    Jason.OrderedObject.new([
      {:type, "tokenDelegate"},
      {:signatureChainId, UserSigned.signature_chain_id()},
      {:hyperliquidChain, UserSigned.hyperliquid_chain(is_mainnet)},
      {:validator, validator},
      {:wei, wei},
      {:isUndelegate, is_undelegate},
      {:nonce, nonce}
    ])
  end

  @doc false
  def sign(private_key, validator, is_undelegate, wei, nonce, is_mainnet \\ nil) do
    UserSigned.sign(
      private_key,
      @primary_type,
      @fields,
      [
        {"validator", validator},
        {"wei", wei},
        {"isUndelegate", is_undelegate},
        {"nonce", nonce}
      ],
      is_mainnet
    )
  end
end
