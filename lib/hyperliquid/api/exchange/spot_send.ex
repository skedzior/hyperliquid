defmodule Hyperliquid.Api.Exchange.SpotSend do
  @moduledoc """
  Send spot tokens to another address.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Transport.Http

  @primary_type "HyperliquidTransaction:SpotSend"
  @types [
    %{name: "hyperliquidChain", type: "string"},
    %{name: "destination", type: "string"},
    %{name: "token", type: "string"},
    %{name: "amount", type: "string"},
    %{name: "time", type: "uint64"}
  ]

  @doc """
  Send spot tokens to another address.

  ## Parameters
    - `destination`: Destination address
    - `token`: Token identifier (e.g., "USDC:0xeb62eee3685fc4c43992febcd9e75443")
    - `amount`: Amount to send (string or number)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:expected_address` - When provided, validates the private key derives to this address

  ## Returns
    - `{:ok, response}` - Transfer result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = SpotSend.request("0x...", "HYPE:0x...", "10.0")

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  def request(destination, token, amount, opts \\ []) do
    private_key = KeyUtils.resolve_and_validate!(opts)
    amount = to_string(amount)
    time = generate_nonce()
    is_mainnet = Config.mainnet?()

    hyperliquid_chain = if(is_mainnet, do: "Mainnet", else: "Testnet")

    message = %{
      hyperliquidChain: hyperliquid_chain,
      destination: destination,
      token: token,
      amount: amount,
      time: time
    }

    with {:ok, signature} <- UserSigned.sign(private_key, @primary_type, @types, message) do
      # Field order for the request body: type, signatureChainId,
      # hyperliquidChain, destination, token, amount, time.
      action =
        Jason.OrderedObject.new([
          {:type, "spotSend"},
          {:signatureChainId, UserSigned.signature_chain_id()},
          {:hyperliquidChain, hyperliquid_chain},
          {:destination, destination},
          {:token, token},
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
