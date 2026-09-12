defmodule Hyperliquid.Api.Exchange.LinkStakingUser do
  @moduledoc """
  Link staking and trading accounts for fee-discount attribution.

  `linkStakingUser` is a **user-signed** (EIP-712) action, not an L1 msgpack
  action. It is signed under `HyperliquidTransaction:LinkStakingUser` with the
  fields `hyperliquidChain`, `user`, `isFinalize`, `nonce`, matching
  `@nktkas/hyperliquid`. Until the 2026-09 API sync this module built and hashed an L1 action
  (`{type, linkTo}`) — the field name (`linkTo`) did not exist on the wire and
  the signing scheme was wrong.

  The link is two-sided:

    * the **trading** user initiates with `is_finalize: false`, passing the
      staking account address;
    * the **staking** user finalizes with `is_finalize: true`, passing the
      trading account address. Finalizing is permanent.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/trading/fees#staking-linking
  """

  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http
  alias Hyperliquid.Utils

  @primary_type "HyperliquidTransaction:LinkStakingUser"
  @fields [{"user", "address"}, {"isFinalize", "bool"}, {"nonce", "uint64"}]

  @doc """
  Link staking and trading accounts.

  ## Parameters
    - `user`: The counterpart address — the staking account when initiating,
      the trading account when finalizing (`"0x..."`)
    - `is_finalize`: `false` to initiate (trading user), `true` to finalize
      (staking user)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:expected_address` - When provided, validates the private key derives to this address

  ## Returns
    - `{:ok, response}` - Link result
    - `{:error, term()}` - Error details

  ## Examples

      # trading user initiates
      {:ok, result} = LinkStakingUser.request("0xstaking...", false)

      # staking user finalizes
      {:ok, result} = LinkStakingUser.request("0xtrading...", true)
  """
  def request(user, is_finalize, opts \\ []) when is_binary(user) and is_boolean(is_finalize) do
    private_key = KeyUtils.resolve_and_validate!(opts)
    user = String.downcase(user)
    nonce = Utils.generate_nonce()
    is_mainnet = Config.mainnet?()

    with {:ok, signature} <- sign(private_key, user, is_finalize, nonce, is_mainnet) do
      Http.user_signed_request(
        build_action(user, is_finalize, nonce, is_mainnet),
        signature,
        nonce,
        opts
      )
    end
  end

  @doc """
  The wire action, in the canonical field order
  (`type`, `signatureChainId`, `hyperliquidChain`, `user`, `isFinalize`, `nonce`).
  """
  def build_action(user, is_finalize, nonce, is_mainnet \\ nil) do
    Jason.OrderedObject.new([
      {:type, "linkStakingUser"},
      {:signatureChainId, UserSigned.signature_chain_id()},
      {:hyperliquidChain, UserSigned.hyperliquid_chain(is_mainnet)},
      {:user, user},
      {:isFinalize, is_finalize},
      {:nonce, nonce}
    ])
  end

  @doc false
  def sign(private_key, user, is_finalize, nonce, is_mainnet \\ nil) do
    UserSigned.sign(
      private_key,
      @primary_type,
      @fields,
      [{"user", user}, {"isFinalize", is_finalize}, {"nonce", nonce}],
      is_mainnet
    )
  end
end
