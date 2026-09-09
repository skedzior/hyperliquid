defmodule Hyperliquid.Api.Exchange.StakingLinkDisableTradingUser do
  @moduledoc """
  Permanently disable a linked trading user, locking its funds.

  Sent by the **staking user**. After one year of locking, the trading user's funds are
  automatically transferred to the staking user. **This action is irreversible.**

  Companion to `Hyperliquid.Api.Exchange.LinkStakingUser` (which is L1-signed); this
  action is **user-signed EIP-712** with primary type
  `HyperliquidTransaction:StakingLinkDisableTradingUser`:

      hyperliquidChain  string
      tradingUser       address
      nonce             uint64

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/trading/fees#staking-linking
  """

  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http
  alias Hyperliquid.Utils

  @primary_type "HyperliquidTransaction:StakingLinkDisableTradingUser"
  @fields [{"tradingUser", "address"}, {"nonce", "uint64"}]

  @doc """
  Permanently disable a linked trading user.

  ## Parameters
    - `trading_user`: Trading user address to disable (`"0x..."`)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:expected_address` - When provided, validates the private key derives to this address

  ## Returns
    - `{:ok, response}` - Result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = StakingLinkDisableTradingUser.request("0x...")
  """
  def request(trading_user, opts \\ []) do
    private_key = KeyUtils.resolve_and_validate!(opts)
    trading_user = String.downcase(trading_user)
    nonce = Utils.generate_nonce()
    is_mainnet = Config.mainnet?()

    with {:ok, signature} <- sign(private_key, trading_user, nonce, is_mainnet) do
      Http.user_signed_request(
        build_action(trading_user, nonce, is_mainnet),
        signature,
        nonce,
        opts
      )
    end
  end

  @doc """
  The wire action, in the canonical field order
  (`type`, `signatureChainId`, `hyperliquidChain`, `tradingUser`, `nonce`).
  """
  def build_action(trading_user, nonce, is_mainnet \\ nil) do
    Jason.OrderedObject.new([
      {:type, "stakingLinkDisableTradingUser"},
      {:signatureChainId, UserSigned.signature_chain_id()},
      {:hyperliquidChain, UserSigned.hyperliquid_chain(is_mainnet)},
      {:tradingUser, trading_user},
      {:nonce, nonce}
    ])
  end

  @doc false
  # Exposed for tests: the EIP-712 primary type used for this action.
  def primary_type, do: @primary_type

  @doc false
  # Exposed for tests: the EIP-712 type table used for this action, as built by
  # `Hyperliquid.Api.Exchange.UserSigned` from `@fields`.
  def eip712_types do
    %{
      "EIP712Domain" => [
        %{name: "name", type: "string"},
        %{name: "version", type: "string"},
        %{name: "chainId", type: "uint256"},
        %{name: "verifyingContract", type: "address"}
      ],
      @primary_type =>
        [%{name: "hyperliquidChain", type: "string"}] ++
          Enum.map(@fields, fn {name, type} -> %{name: name, type: type} end)
    }
  end

  @doc false
  def sign(private_key, trading_user, nonce, is_mainnet \\ nil) do
    UserSigned.sign(
      private_key,
      @primary_type,
      @fields,
      [{"tradingUser", trading_user}, {"nonce", nonce}],
      is_mainnet
    )
  end
end
