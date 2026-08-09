defmodule Hyperliquid.Api.Exchange.UsdSend do
  @moduledoc """
  Send USD to another address.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Transport.Http

  @primary_type "HyperliquidTransaction:UsdSend"
  @types [
    %{name: "hyperliquidChain", type: "string"},
    %{name: "destination", type: "string"},
    %{name: "amount", type: "string"},
    %{name: "time", type: "uint64"}
  ]

  @doc """
  Send USD to another address.

  ## Parameters
    - `destination`: Destination address
    - `amount`: Amount to send (string or number, e.g. 1 = $1)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:expected_address` - When provided, validates the private key derives to this address

  ## Returns
    - `{:ok, response}` - Transfer result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = UsdSend.request("0x...", "100.0")
      {:ok, result} = UsdSend.request("0x...", "100.0", private_key: "abc...")

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  def request(destination, amount, opts \\ []) do
    private_key = KeyUtils.resolve_and_validate!(opts)
    amount = to_string(amount)
    time = generate_nonce()
    is_mainnet = Config.mainnet?()

    hyperliquid_chain = if(is_mainnet, do: "Mainnet", else: "Testnet")

    message = %{
      hyperliquidChain: hyperliquid_chain,
      destination: destination,
      amount: amount,
      time: time
    }

    with {:ok, signature} <-
           UserSigned.sign(private_key, @primary_type, @types, message) do
      # Field order for the request body: type, signatureChainId,
      # hyperliquidChain, destination, amount, time.
      action =
        Jason.OrderedObject.new([
          {:type, "usdSend"},
          {:signatureChainId, UserSigned.signature_chain_id()},
          {:hyperliquidChain, hyperliquid_chain},
          {:destination, destination},
          {:amount, amount},
          {:time, time}
        ])

      Http.user_signed_request(action, signature, time, opts)
    end
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
