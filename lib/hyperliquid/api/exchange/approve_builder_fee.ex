defmodule Hyperliquid.Api.Exchange.ApproveBuilderFee do
  @moduledoc """
  Approve a builder to charge fees.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Transport.Http

  @primary_type "HyperliquidTransaction:ApproveBuilderFee"
  @types [
    %{name: "hyperliquidChain", type: "string"},
    %{name: "maxFeeRate", type: "string"},
    %{name: "builder", type: "address"},
    %{name: "nonce", type: "uint64"}
  ]

  @doc """
  Approve a builder to charge fees.

  ## Parameters
    - `builder`: Builder address
    - `max_fee_rate`: Maximum fee rate in basis points (e.g., "0.001%" = "0.00001")
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:expected_address` - When provided, validates the private key derives to this address

  ## Returns
    - `{:ok, response}` - Result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = ApproveBuilderFee.request("0x...", "0.001")

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  def request(builder, max_fee_rate, opts \\ []) do
    private_key = KeyUtils.resolve_and_validate!(opts)
    nonce = generate_nonce()
    is_mainnet = Config.mainnet?()

    hyperliquid_chain = if(is_mainnet, do: "Mainnet", else: "Testnet")

    message = %{
      hyperliquidChain: hyperliquid_chain,
      maxFeeRate: max_fee_rate,
      builder: builder,
      nonce: nonce
    }

    with {:ok, signature} <- UserSigned.sign(private_key, @primary_type, @types, message) do
      action = %{
        type: "approveBuilderFee",
        hyperliquidChain: hyperliquid_chain,
        signatureChainId: UserSigned.signature_chain_id(),
        builder: builder,
        maxFeeRate: max_fee_rate,
        nonce: nonce
      }

      Http.user_signed_request(action, signature, nonce, opts)
    end
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
