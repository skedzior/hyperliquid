defmodule Hyperliquid.Api.Exchange.UserSetAbstraction do
  @moduledoc """
  Set account abstraction mode for a user.

  Allows setting the abstraction mode to disabled, unifiedAccount, or portfolioMargin.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @valid_modes ["disabled", "unifiedAccount", "portfolioMargin"]

  @doc """
  Set account abstraction mode.

  ## Parameters
    - `abstraction`: Mode string - "disabled", "unifiedAccount", or "portfolioMargin"
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)

  ## Returns
    - `{:ok, response}` - Result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = UserSetAbstraction.request("unifiedAccount")
  """
  def request(abstraction, opts \\ []) when abstraction in @valid_modes do
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
      "HyperliquidTransaction:UserSetAbstraction" => [
        %{name: "hyperliquidChain", type: "string"},
        %{name: "abstraction", type: "string"},
        %{name: "nonce", type: "uint64"}
      ]
    }

    message = %{
      hyperliquidChain: if(is_mainnet, do: "Mainnet", else: "Testnet"),
      abstraction: abstraction,
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
             "HyperliquidTransaction:UserSetAbstraction"
           ) do
      action = %{
        type: "userSetAbstraction",
        hyperliquidChain: if(is_mainnet, do: "Mainnet", else: "Testnet"),
        signatureChainId: Hyperliquid.Config.signature_chain_id_hex(),
        abstraction: abstraction,
        nonce: nonce
      }

      Http.user_signed_request(action, signature, nonce, opts)
    end
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
