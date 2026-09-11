defmodule Hyperliquid.Api.Exchange.UserDexAbstraction do
  @moduledoc """
  Enable or disable HIP-3 DEX abstraction for a user.

  `userDexAbstraction` is a **user-signed** (EIP-712) action, not an L1 msgpack
  action. It is signed under `HyperliquidTransaction:UserDexAbstraction` with the
  fields `hyperliquidChain`, `user`, `enabled`, `nonce`, matching
  `@nktkas/hyperliquid` and `hyperliquid-python-sdk`
  (`USER_DEX_ABSTRACTION_SIGN_TYPES`). Until the 2026-09 API sync this module built and hashed
  an L1 action (`{type, enabled}`), omitting `user` entirely.

  This is the exchange-side action. The info-side query lives at
  `Hyperliquid.Api.Info.UserDexAbstraction`.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint#enable-hip-3-dex-abstraction

  ## Usage

      {:ok, result} = UserDexAbstraction.request("0xabc...", true)
      {:ok, result} = UserDexAbstraction.request("0xabc...", false)
  """

  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http
  alias Hyperliquid.Utils

  @primary_type "HyperliquidTransaction:UserDexAbstraction"
  @fields [{"user", "address"}, {"enabled", "bool"}, {"nonce", "uint64"}]

  @doc """
  Enable or disable DEX abstraction for a user.

  ## Parameters
    - `user`: Address the setting applies to (`"0x..."`)
    - `enabled`: `true` to enable DEX abstraction, `false` to disable
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:expected_address` - When provided, validates the private key derives to this address

  ## Returns
    - `{:ok, response}` - Result
    - `{:error, term()}` - Error details
  """
  def request(user, enabled, opts \\ []) when is_binary(user) and is_boolean(enabled) do
    private_key = KeyUtils.resolve_and_validate!(opts)
    user = String.downcase(user)
    nonce = Utils.generate_nonce()
    is_mainnet = Config.mainnet?()

    with {:ok, signature} <- sign(private_key, user, enabled, nonce, is_mainnet) do
      Http.user_signed_request(
        build_action(user, enabled, nonce, is_mainnet),
        signature,
        nonce,
        opts
      )
    end
  end

  @doc """
  The wire action, in the canonical field order
  (`type`, `signatureChainId`, `hyperliquidChain`, `user`, `enabled`, `nonce`).
  """
  def build_action(user, enabled, nonce, is_mainnet \\ nil) do
    Jason.OrderedObject.new([
      {:type, "userDexAbstraction"},
      {:signatureChainId, UserSigned.signature_chain_id()},
      {:hyperliquidChain, UserSigned.hyperliquid_chain(is_mainnet)},
      {:user, user},
      {:enabled, enabled},
      {:nonce, nonce}
    ])
  end

  @doc false
  def sign(private_key, user, enabled, nonce, is_mainnet \\ nil) do
    UserSigned.sign(
      private_key,
      @primary_type,
      @fields,
      [{"user", user}, {"enabled", enabled}, {"nonce", nonce}],
      is_mainnet
    )
  end
end
