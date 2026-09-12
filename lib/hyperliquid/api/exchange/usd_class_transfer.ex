defmodule Hyperliquid.Api.Exchange.UsdClassTransfer do
  @moduledoc """
  Transfer USD between spot and perp accounts.

  `usdClassTransfer` is a **user-signed** (EIP-712) action, not an L1 msgpack
  action. It is signed under `HyperliquidTransaction:UsdClassTransfer` with the
  fields `hyperliquidChain`, `amount`, `toPerp`, `nonce`, matching
  `@nktkas/hyperliquid` and `hyperliquid-python-sdk`. Until the 2026-09 API sync this module
  built and hashed an L1 action (`{type, amount, toPerp}`); those signatures
  could never have been recovered to the sending address.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint#transfer-from-spot-account-to-perp-account-and-vice-versa
  """

  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http
  alias Hyperliquid.Utils

  @primary_type "HyperliquidTransaction:UsdClassTransfer"
  @fields [{"amount", "string"}, {"toPerp", "bool"}, {"nonce", "uint64"}]

  @doc """
  Transfer USD between spot and perp accounts.

  ## Parameters
    - `amount`: Amount to transfer (string or number, 1 = $1). To transfer on
      behalf of a sub-account, suffix with ` subaccount:<address>`.
    - `to_perp`: `true` to transfer spot -> perp, `false` for perp -> spot
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:expected_address` - When provided, validates the private key derives to this address

  ## Returns
    - `{:ok, response}` - Transfer result
    - `{:error, term()}` - Error details

  ## Examples

      # Transfer to perp
      {:ok, result} = UsdClassTransfer.request("100.0", true)

      # Transfer to spot
      {:ok, result} = UsdClassTransfer.request("100.0", false)
  """
  def request(amount, to_perp, opts \\ []) do
    private_key = KeyUtils.resolve_and_validate!(opts)
    amount = Utils.float_to_string(amount)
    nonce = Utils.generate_nonce()
    is_mainnet = Config.mainnet?()

    with {:ok, signature} <- sign(private_key, amount, to_perp, nonce, is_mainnet) do
      Http.user_signed_request(
        build_action(amount, to_perp, nonce, is_mainnet),
        signature,
        nonce,
        opts
      )
    end
  end

  @doc """
  The wire action, in the canonical field order
  (`type`, `signatureChainId`, `hyperliquidChain`, `amount`, `toPerp`, `nonce`).
  """
  def build_action(amount, to_perp, nonce, is_mainnet \\ nil) do
    Jason.OrderedObject.new([
      {:type, "usdClassTransfer"},
      {:signatureChainId, UserSigned.signature_chain_id()},
      {:hyperliquidChain, UserSigned.hyperliquid_chain(is_mainnet)},
      {:amount, amount},
      {:toPerp, to_perp},
      {:nonce, nonce}
    ])
  end

  @doc false
  def sign(private_key, amount, to_perp, nonce, is_mainnet \\ nil) do
    UserSigned.sign(
      private_key,
      @primary_type,
      @fields,
      [{"amount", amount}, {"toPerp", to_perp}, {"nonce", nonce}],
      is_mainnet
    )
  end
end
