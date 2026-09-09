defmodule Hyperliquid.Api.Exchange.Withdraw3 do
  @moduledoc """
  Initiate a withdrawal request.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http

  @doc """
  Initiate a withdrawal request.

  ## Parameters
    - `destination`: Destination address
    - `amount`: Amount to withdraw (string or number, e.g. 1 = $1)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:expected_address` - When provided, validates the private key derives to this address

  ## Returns
    - `{:ok, response}` - Withdrawal result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = Withdraw3.request("0x...", "100.0")

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  def request(destination, amount, opts \\ []) do
    private_key = KeyUtils.resolve_and_validate!(opts)
    amount = to_string(amount)
    time = generate_nonce()
    is_mainnet = Config.mainnet?()

    action =
      Jason.OrderedObject.new([
        {:type, "withdraw3"},
        {:signatureChainId, UserSigned.signature_chain_id()},
        {:hyperliquidChain, UserSigned.hyperliquid_chain(is_mainnet)},
        {:destination, destination},
        {:amount, amount},
        {:time, time}
      ])

    with {:ok, signature} <-
           UserSigned.sign(
             private_key,
             "HyperliquidTransaction:Withdraw",
             [{"destination", "string"}, {"amount", "string"}, {"time", "uint64"}],
             [{"destination", destination}, {"amount", amount}, {"time", time}],
             is_mainnet
           ) do
      Http.user_signed_request(action, signature, time, opts)
    end
  end

  defp generate_nonce do
    Hyperliquid.Utils.generate_nonce()
  end
end
