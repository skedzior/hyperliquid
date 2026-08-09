defmodule Hyperliquid.Api.Exchange.ValidatorL1Stream do
  @moduledoc """
  Validator vote on risk-free rate for quote assets.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @doc """
  Submit a validator vote on the risk-free rate.

  ## Parameters
    - `risk_free_rate`: Rate as string (e.g., "0.05")
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)

  ## Returns
    - `{:ok, response}` - Vote result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = ValidatorL1Stream.request("0.05")
  """
  def request(risk_free_rate, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "validatorL1Stream",
      riskFreeRate: risk_free_rate
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
