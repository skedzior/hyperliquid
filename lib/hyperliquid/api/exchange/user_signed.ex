defmodule Hyperliquid.Api.Exchange.UserSigned do
  @moduledoc """
  Shared EIP-712 signing for user-signed exchange actions.

  User-signed actions (withdrawals, transfers, agent approvals) are signed over
  typed data rather than over the msgpack of the action, so field order does not
  affect the signature — but the EIP-712 domain does.

  The domain's `chainId` and the action's `signatureChainId` must always agree:
  the exchange rebuilds the domain from `signatureChainId` to recover the signer,
  so if they drift the API recovers the wrong address and rejects the action.
  Both come from `Hyperliquid.Config.signature_chain_id/0`, which is what keeps
  them in step.
  """

  alias Hyperliquid.{Config, Signer}

  @verifying_contract "0x0000000000000000000000000000000000000000"

  @doc """
  The EIP-712 domain used for every user-signed action.
  """
  @spec domain() :: map()
  def domain do
    %{
      name: "HyperliquidSignTransaction",
      version: "1",
      chainId: Config.signature_chain_id(),
      verifyingContract: @verifying_contract
    }
  end

  @doc """
  `"Mainnet"` or `"Testnet"`, the field that actually selects the network.
  """
  @spec hyperliquid_chain() :: String.t()
  def hyperliquid_chain, do: if(Config.mainnet?(), do: "Mainnet", else: "Testnet")

  @doc """
  The `signatureChainId` field to send in the action body.
  """
  @spec signature_chain_id() :: String.t()
  def signature_chain_id, do: Config.signature_chain_id_hex()

  @doc """
  Sign a user-signed action's typed data.

  ## Parameters
    - `private_key`: Private key for signing
    - `primary_type`: EIP-712 primary type, e.g. `"HyperliquidTransaction:UsdSend"`
    - `types`: List of `%{name: ..., type: ...}` field descriptors, in order
    - `message`: The message to sign

  ## Returns
    - `{:ok, %{r: ..., s: ..., v: ...}}`
    - `{:error, {:signing_error, term()}}`
  """
  @spec sign(String.t(), String.t(), [map()], map()) ::
          {:ok, map()} | {:error, term()}
  def sign(private_key, primary_type, types, message) do
    with {:ok, domain_json} <- Jason.encode(domain()),
         {:ok, types_json} <- Jason.encode(%{primary_type => types}),
         {:ok, message_json} <- Jason.encode(message) do
      case Signer.sign_typed_data(
             private_key,
             domain_json,
             types_json,
             message_json,
             primary_type
           ) do
        %{"r" => r, "s" => s, "v" => v} -> {:ok, %{r: r, s: s, v: v}}
        error -> {:error, {:signing_error, error}}
      end
    end
  end
end
