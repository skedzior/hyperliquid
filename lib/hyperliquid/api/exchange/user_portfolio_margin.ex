defmodule Hyperliquid.Api.Exchange.UserPortfolioMargin do
  @moduledoc """
  Enable or disable portfolio margin mode for a user.

  `userPortfolioMargin` is a **user-signed** (EIP-712) action, not an L1 msgpack
  action. It is signed under `HyperliquidTransaction:UserPortfolioMargin` with
  the fields `hyperliquidChain`, `user`, `enabled`, `nonce`, matching
  `@nktkas/hyperliquid`. Before v0.2.4 this module built and hashed an L1 action
  (`{type, on}`) — both the field name and the signing scheme were wrong, so
  those signatures could never have been recovered to the sending address.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/trading/portfolio-margin

  ## Usage

      {:ok, result} = UserPortfolioMargin.request("0xabc...", true)   # enable
      {:ok, result} = UserPortfolioMargin.request("0xabc...", false)  # disable
  """

  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http
  alias Hyperliquid.Utils

  @primary_type "HyperliquidTransaction:UserPortfolioMargin"
  @fields [{"user", "address"}, {"enabled", "bool"}, {"nonce", "uint64"}]

  @doc """
  Enable or disable portfolio margin mode.

  ## Parameters
    - `user`: Address the setting applies to (`"0x..."`)
    - `enabled`: `true` to enable portfolio margin, `false` to disable
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
      {:type, "userPortfolioMargin"},
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
