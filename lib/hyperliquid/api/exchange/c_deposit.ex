defmodule Hyperliquid.Api.Exchange.CDeposit do
  @moduledoc """
  Deposit native token from spot account into staking balance.

  `cDeposit` is a **user-signed** (EIP-712) action, signed under
  `HyperliquidTransaction:CDeposit` with the fields `hyperliquidChain`, `wei`
  (uint64), `nonce` (uint64), matching `@nktkas/hyperliquid` (`CDepositTypes`).

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http
  alias Hyperliquid.Utils

  @primary_type "HyperliquidTransaction:CDeposit"
  @fields [{"wei", "uint64"}, {"nonce", "uint64"}]

  @doc """
  Deposit native token from spot account into staking balance.

  ## Parameters
    - `wei`: Amount in wei to deposit (float * 1e8)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)

  ## Returns
    - `{:ok, response}` - Deposit result
    - `{:error, term()}` - Error details

  ## Examples

      # Deposit 1 HYPE (1 * 1e8 = 100000000)
      {:ok, result} = CDeposit.request(100_000_000, private_key: private_key)
  """
  def request(wei, opts \\ []) do
    private_key = KeyUtils.resolve_private_key!(opts)
    nonce = Utils.generate_nonce()
    is_mainnet = Config.mainnet?()

    with {:ok, signature} <- sign(private_key, wei, nonce, is_mainnet) do
      Http.user_signed_request(build_action(wei, nonce, is_mainnet), signature, nonce, opts)
    end
  end

  @doc """
  The wire action, in the canonical field order
  (`type`, `signatureChainId`, `hyperliquidChain`, `wei`, `nonce`).
  """
  def build_action(wei, nonce, is_mainnet \\ nil) do
    Jason.OrderedObject.new([
      {:type, "cDeposit"},
      {:signatureChainId, UserSigned.signature_chain_id()},
      {:hyperliquidChain, UserSigned.hyperliquid_chain(is_mainnet)},
      {:wei, wei},
      {:nonce, nonce}
    ])
  end

  @doc false
  def sign(private_key, wei, nonce, is_mainnet \\ nil) do
    UserSigned.sign(
      private_key,
      @primary_type,
      @fields,
      [{"wei", wei}, {"nonce", nonce}],
      is_mainnet
    )
  end
end
