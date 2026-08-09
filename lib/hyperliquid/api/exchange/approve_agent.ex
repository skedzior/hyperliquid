defmodule Hyperliquid.Api.Exchange.ApproveAgent do
  @moduledoc """
  Approve an agent to trade on behalf of your account.

  Agents are sub-keys that can be granted trading permissions without exposing
  your main private key.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Transport.Http

  @primary_type "HyperliquidTransaction:ApproveAgent"
  @types [
    %{name: "hyperliquidChain", type: "string"},
    %{name: "agentAddress", type: "address"},
    %{name: "agentName", type: "string"},
    %{name: "nonce", type: "uint64"}
  ]

  # ===================== Types =====================

  @type approve_opts :: [
          agent_name: String.t(),
          private_key: String.t(),
          expected_address: String.t()
        ]

  @type approve_response :: %{
          status: String.t(),
          response: map()
        }

  # ===================== Request Functions =====================

  @doc """
  Approve an agent to trade on your behalf.

  ## Parameters
    - `agent_address`: Address of the agent to approve (0x...)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:expected_address` - When provided, validates the private key derives to this address
    - `:agent_name` - Human-readable name for the agent

  ## Returns
    - `{:ok, response}` - Approval result
    - `{:error, term()}` - Error details

  ## Examples

      # Approve agent with default name
      {:ok, result} = ApproveAgent.approve("0x1234...")

      # Approve agent with custom name
      {:ok, result} = ApproveAgent.approve("0x1234...", agent_name: "Trading Bot")

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  @spec approve(String.t(), approve_opts()) ::
          {:ok, approve_response()} | {:error, term()}
  def approve(agent_address, opts \\ []) do
    private_key = KeyUtils.resolve_and_validate!(opts)
    agent_name = Keyword.get(opts, :agent_name)
    nonce = generate_nonce()

    # Normalize address to checksum format
    agent_address = Signer.to_checksum_address(agent_address)

    with {:ok, signature} <- sign_approve(private_key, agent_address, agent_name, nonce) do
      action = build_action(agent_address, agent_name, nonce)
      # L1 actions don't use expires_after
      Http.exchange_request(action, signature, nonce, nil, nil)
    end
  end

  # ===================== Action Building =====================

  defp build_action(agent_address, agent_name, nonce) do
    is_mainnet = Config.mainnet?()

    action = %{
      type: "approveAgent",
      hyperliquidChain: if(is_mainnet, do: "Mainnet", else: "Testnet"),
      signatureChainId: UserSigned.signature_chain_id(),
      agentAddress: agent_address,
      nonce: nonce
    }

    if agent_name do
      Map.put(action, :agentName, agent_name)
    else
      action
    end
  end

  # ===================== Signing =====================

  defp sign_approve(private_key, agent_address, agent_name, nonce) do
    message = %{
      hyperliquidChain: UserSigned.hyperliquid_chain(),
      agentAddress: agent_address,
      # An unnamed agent signs over the empty string, which is also how the NIF
      # decoded a nil name.
      agentName: agent_name || "",
      nonce: nonce
    }

    UserSigned.sign(private_key, @primary_type, @types, message)
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
