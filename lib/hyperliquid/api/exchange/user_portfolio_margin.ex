defmodule Hyperliquid.Api.Exchange.UserPortfolioMargin do
  @moduledoc """
  Enable or disable portfolio margin mode for the calling user.

  Portfolio margin allows cross-margining across perps positions using a
  portfolio risk model rather than per-position margin requirements.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint

  ## Usage

      {:ok, result} = UserPortfolioMargin.request(true)   # enable
      {:ok, result} = UserPortfolioMargin.request(false)  # disable
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @doc """
  Enable or disable portfolio margin mode.

  ## Parameters
    - `on`: `true` to enable portfolio margin, `false` to disable
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)

  ## Returns
    - `{:ok, response}` - Result
    - `{:error, term()}` - Error details
  """
  def request(on, opts \\ []) do
    private_key = KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "userPortfolioMargin",
      on: on
    }

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after) do
      Http.exchange_request(action, signature, nonce, vault_address, expires_after, opts)
    end
  end

  defp sign_action(private_key, action_json, nonce, vault_address, expires_after) do
    is_mainnet = Config.mainnet?()

    case Signer.sign_exchange_action_ex(
           private_key,
           action_json,
           nonce,
           is_mainnet,
           vault_address,
           expires_after
         ) do
      %{"r" => r, "s" => s, "v" => v} ->
        {:ok, %{r: r, s: s, v: v}}

      error ->
        {:error, {:signing_error, error}}
    end
  end

  defp generate_nonce, do: System.system_time(:millisecond)
end
