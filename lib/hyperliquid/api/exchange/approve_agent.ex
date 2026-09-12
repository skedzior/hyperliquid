defmodule Hyperliquid.Api.Exchange.ApproveAgent do
  @moduledoc """
  Approve an agent to trade on behalf of your account.

  Agents are sub-keys that can be granted trading permissions without exposing
  your main private key.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

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
      Http.user_signed_request(
        build_action(agent_address, agent_name, nonce),
        signature,
        nonce,
        opts
      )
    end
  end

  # ===================== Action Building =====================

  defp build_action(agent_address, agent_name, nonce) do
    is_mainnet = Config.mainnet?()

    fields = [
      {:type, "approveAgent"},
      {:signatureChainId, UserSigned.signature_chain_id()},
      {:hyperliquidChain, UserSigned.hyperliquid_chain(is_mainnet)},
      {:agentAddress, agent_address}
    ]

    fields = if agent_name, do: fields ++ [{:agentName, agent_name}], else: fields

    Jason.OrderedObject.new(fields ++ [{:nonce, nonce}])
  end

  # ===================== Signing =====================

  defp sign_approve(private_key, agent_address, agent_name, nonce) do
    # A missing agentName hashes as the empty string (matching nktkas and the
    # Python SDK), but is omitted from the wire action.
    UserSigned.sign(
      private_key,
      "HyperliquidTransaction:ApproveAgent",
      [{"agentAddress", "address"}, {"agentName", "string"}, {"nonce", "uint64"}],
      [{"agentAddress", agent_address}, {"agentName", agent_name || ""}, {"nonce", nonce}],
      Config.mainnet?()
    )
  end

  defp generate_nonce do
    Hyperliquid.Utils.generate_nonce()
  end
end
