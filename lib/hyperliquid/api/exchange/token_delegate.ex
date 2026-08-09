defmodule Hyperliquid.Api.Exchange.TokenDelegate do
  @moduledoc """
  Delegate or undelegate stake to/from a validator.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @doc """
  Delegate or undelegate stake to/from a validator.

  ## Parameters
    - `validator`: Validator address (0x...)
    - `is_undelegate`: true to undelegate, false to delegate
    - `wei`: Amount in wei (integer)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)

  ## Returns
    - `{:ok, response}` - Delegation result
    - `{:error, term()}` - Error details

  ## Examples

      # Delegate 1 HYPE
      {:ok, result} = TokenDelegate.request("0x...", false, 100_000_000)

      # Undelegate
      {:ok, result} = TokenDelegate.request("0x...", true, 100_000_000)
  """
  def request(validator, is_undelegate, wei, opts \\ []) do
    private_key = KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    is_mainnet = Config.mainnet?()

    domain = %{
      name: "HyperliquidSignTransaction",
      version: "1",
      chainId: Hyperliquid.Config.signature_chain_id(),
      verifyingContract: "0x0000000000000000000000000000000000000000"
    }

    types = %{
      "HyperliquidTransaction:TokenDelegate" => [
        %{name: "hyperliquidChain", type: "string"},
        %{name: "validator", type: "string"},
        %{name: "isUndelegate", type: "bool"},
        %{name: "wei", type: "uint64"},
        %{name: "nonce", type: "uint64"}
      ]
    }

    message = %{
      hyperliquidChain: if(is_mainnet, do: "Mainnet", else: "Testnet"),
      validator: validator,
      isUndelegate: is_undelegate,
      wei: wei,
      nonce: nonce
    }

    with {:ok, domain_json} <- Jason.encode(domain),
         {:ok, types_json} <- Jason.encode(types),
         {:ok, message_json} <- Jason.encode(message),
         {:ok, signature} <-
           KeyUtils.sign_typed_data(
             private_key,
             domain_json,
             types_json,
             message_json,
             "HyperliquidTransaction:TokenDelegate"
           ) do
      action = %{
        type: "tokenDelegate",
        hyperliquidChain: if(is_mainnet, do: "Mainnet", else: "Testnet"),
        signatureChainId: Hyperliquid.Config.signature_chain_id_hex(),
        validator: validator,
        isUndelegate: is_undelegate,
        wei: wei,
        nonce: nonce
      }

      Http.user_signed_request(action, signature, nonce, opts)
    end
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
