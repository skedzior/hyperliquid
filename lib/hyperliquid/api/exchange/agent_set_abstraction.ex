defmodule Hyperliquid.Api.Exchange.AgentSetAbstraction do
  @moduledoc """
  Agent-triggered abstraction mode configuration.

  Sets the account abstraction mode via an agent. Uses abbreviated mode codes:
  "i" = disabled, "u" = unifiedAccount, "p" = portfolioMargin.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
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
    Hyperliquid.Api.Exchange.Action.sign_json(
      private_key,
      action_json,
      nonce,
      vault_address,
      expires_after
    )
  end

  defp generate_nonce do
    Hyperliquid.Utils.generate_nonce()
  end
end
