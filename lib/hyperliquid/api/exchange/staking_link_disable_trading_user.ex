defmodule Hyperliquid.Api.Exchange.StakingLinkDisableTradingUser do
  @moduledoc """
  Disable a trading user previously linked to a staking account.

  The inverse of `Hyperliquid.Api.Exchange.LinkStakingUser`. Unlike that action
  this one is user-signed (EIP-712 typed data), so it must be signed with the
  master key rather than an agent wallet.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint

  ## Usage

      {:ok, result} = StakingLinkDisableTradingUser.request("0xabc...")
  """

  alias Hyperliquid.{Config, Signer, Utils}
  alias Hyperliquid.Transport.Http

  @primary_type "HyperliquidTransaction:StakingLinkDisableTradingUser"

  @doc """
  Disable a linked trading user.

  ## Parameters
    - `trading_user`: Address of the trading user to disable
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)

  ## Returns
    - `{:ok, response}` - Result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = StakingLinkDisableTradingUser.request("0xabc...")
  """
  @spec request(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def request(trading_user, opts \\ []) when is_binary(trading_user) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    is_mainnet = Config.mainnet?()
    hyperliquid_chain = if is_mainnet, do: "Mainnet", else: "Testnet"

    domain = %{
      name: "HyperliquidSignTransaction",
      version: "1",
      chainId: 42_161,
      verifyingContract: "0x0000000000000000000000000000000000000000"
    }

    types = %{
      @primary_type => [
        %{name: "hyperliquidChain", type: "string"},
        %{name: "tradingUser", type: "address"},
        %{name: "nonce", type: "uint64"}
      ]
    }

    message = %{
      hyperliquidChain: hyperliquid_chain,
      tradingUser: trading_user,
      nonce: nonce
    }

    with {:ok, domain_json} <- Jason.encode(domain),
         {:ok, types_json} <- Jason.encode(types),
         {:ok, message_json} <- Jason.encode(message) do
      case Signer.sign_typed_data(
             private_key,
             domain_json,
             types_json,
             message_json,
             @primary_type
           ) do
        %{"r" => r, "s" => s, "v" => v} ->
          # Field order matters for the request body, so build it explicitly.
          action =
            Jason.OrderedObject.new([
              {:type, "stakingLinkDisableTradingUser"},
              {:signatureChainId, Utils.from_int(42_161)},
              {:hyperliquidChain, hyperliquid_chain},
              {:tradingUser, trading_user},
              {:nonce, nonce}
            ])

          Http.user_signed_request(action, %{r: r, s: s, v: v}, nonce, opts)

        error ->
          {:error, {:signing_error, error}}
      end
    end
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
