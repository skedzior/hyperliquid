defmodule Hyperliquid.Api.Exchange.CWithdraw do
  @moduledoc """
  Withdraw from staking balance back to spot account.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @doc """
  Withdraw from staking balance back to spot account.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `wei`: Amount in wei to withdraw (float * 1e8)
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` - Withdrawal result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = CWithdraw.request(private_key, 100_000_000)
  """
  def request(wei, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    is_mainnet = Config.mainnet?()

    domain = %{
      name: "HyperliquidSignTransaction",
      version: "1",
      chainId: Hyperliquid.Config.signature_chain_id(),
      verifyingContract: "0x0000000000000000000000000000000000000000"
    }

    types = %{
      "HyperliquidTransaction:CWithdraw" => [
        %{name: "hyperliquidChain", type: "string"},
        %{name: "wei", type: "uint64"},
        %{name: "nonce", type: "uint64"}
      ]
    }

    message = %{
      hyperliquidChain: if(is_mainnet, do: "Mainnet", else: "Testnet"),
      wei: wei,
      nonce: nonce
    }

    with {:ok, domain_json} <- Jason.encode(domain),
         {:ok, types_json} <- Jason.encode(types),
         {:ok, message_json} <- Jason.encode(message) do
      sig =
        Signer.sign_typed_data(
          private_key,
          domain_json,
          types_json,
          message_json,
          "HyperliquidTransaction:CWithdraw"
        )

      action = %{
        type: "cWithdraw",
        hyperliquidChain: if(is_mainnet, do: "Mainnet", else: "Testnet"),
        signatureChainId: Hyperliquid.Config.signature_chain_id_hex(),
        wei: wei,
        nonce: nonce
      }

      signature = %{r: sig["r"], s: sig["s"], v: sig["v"]}

      Http.user_signed_request(action, signature, nonce, opts)
    end
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
