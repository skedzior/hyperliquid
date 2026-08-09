defmodule Hyperliquid.Api.Exchange.AgentSetAbstraction do
  @moduledoc """
  Agent-triggered abstraction mode configuration.

  Sets the account abstraction mode via an agent. Uses abbreviated mode codes:
  "i" = disabled, "u" = unifiedAccount, "p" = portfolioMargin.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @valid_modes ["i", "u", "p"]

  @doc """
  Set account abstraction mode via agent.

  ## Parameters
    - `abstraction`: Mode code - "i" (disabled), "u" (unifiedAccount), "p" (portfolioMargin)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)

  ## Returns
    - `{:ok, response}` - Result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = AgentSetAbstraction.request("u")
  """
  def request(abstraction, opts \\ []) when abstraction in @valid_modes do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "agentSetAbstraction",
      abstraction: abstraction
    }

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <- sign_action(private_key, action_json, nonce, nil, expires_after) do
      Http.exchange_request(action, signature, nonce, nil, expires_after, opts)
    end
  end

  defp sign_action(private_key, action_json, nonce, vault_address, expires_after) do
    is_mainnet = Config.mainnet?()

    connection_id =
      Signer.compute_connection_id_ex(action_json, nonce, vault_address, expires_after)

    case Signer.sign_l1_action(private_key, connection_id, is_mainnet) do
      %{"r" => r, "s" => s, "v" => v} ->
        {:ok, %{r: r, s: s, v: v}}

      error ->
        {:error, {:signing_error, error}}
    end
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
