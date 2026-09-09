defmodule Hyperliquid.Api.Exchange.UserSetAbstraction do
  @moduledoc """
  Set account abstraction mode for a user.

  Allows setting the abstraction mode to disabled, unifiedAccount, or portfolioMargin.

  `userSetAbstraction` is a **user-signed** (EIP-712) action, signed under
  `HyperliquidTransaction:UserSetAbstraction` with the fields
  `hyperliquidChain`, `user` (address), `abstraction`, `nonce`, matching
  `@nktkas/hyperliquid` (`UserSetAbstractionTypes`).

  Before v0.2.4 this module omitted the `user` field entirely, so both the
  EIP-712 type hash and the encoded struct were wrong and the signature could
  never have been recovered to the sending address.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http
  alias Hyperliquid.Utils

  @primary_type "HyperliquidTransaction:UserSetAbstraction"
  @fields [{"user", "address"}, {"abstraction", "string"}, {"nonce", "uint64"}]

  @valid_modes ["disabled", "unifiedAccount", "portfolioMargin"]

  @doc """
  Set account abstraction mode.

  ## Parameters
    - `user`: Address the setting applies to (`"0x..."`)
    - `abstraction`: Mode string - "disabled", "unifiedAccount", or "portfolioMargin"
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)

  ## Returns
    - `{:ok, response}` - Result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = UserSetAbstraction.request("0xabc...", "unifiedAccount")
  """
  def request(user, abstraction, opts \\ [])
      when is_binary(user) and abstraction in @valid_modes do
    private_key = KeyUtils.resolve_private_key!(opts)
    user = String.downcase(user)
    nonce = Utils.generate_nonce()
    is_mainnet = Config.mainnet?()

    with {:ok, signature} <- sign(private_key, user, abstraction, nonce, is_mainnet) do
      Http.user_signed_request(
        build_action(user, abstraction, nonce, is_mainnet),
        signature,
        nonce,
        opts
      )
    end
  end

  @doc """
  The wire action, in the canonical field order
  (`type`, `signatureChainId`, `hyperliquidChain`, `user`, `abstraction`, `nonce`).
  """
  def build_action(user, abstraction, nonce, is_mainnet \\ nil) do
    Jason.OrderedObject.new([
      {:type, "userSetAbstraction"},
      {:signatureChainId, UserSigned.signature_chain_id()},
      {:hyperliquidChain, UserSigned.hyperliquid_chain(is_mainnet)},
      {:user, user},
      {:abstraction, abstraction},
      {:nonce, nonce}
    ])
  end

  @doc false
  def sign(private_key, user, abstraction, nonce, is_mainnet \\ nil) do
    UserSigned.sign(
      private_key,
      @primary_type,
      @fields,
      [{"user", user}, {"abstraction", abstraction}, {"nonce", nonce}],
      is_mainnet
    )
  end
end
