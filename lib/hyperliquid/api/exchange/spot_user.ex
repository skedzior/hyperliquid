defmodule Hyperliquid.Api.Exchange.SpotUser do
  @moduledoc """
  User-level spot configuration actions.

  Currently supports one action:
  - `toggle_spot_dusting/2` — Opt in or out of automatic spot dusting

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint

  ## Usage

      # Opt out of spot dusting
      {:ok, result} = SpotUser.toggle_spot_dusting(true)

      # Opt back in
      {:ok, result} = SpotUser.toggle_spot_dusting(false)
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @doc """
  Opt in or out of automatic spot dusting.

  Spot dusting is the automatic conversion of small spot balances (dust) to USDC.

  ## Parameters
    - `opt_out`: `true` to opt out of dusting, `false` to opt back in
    - `opts`: Optional parameters

  ## Options
    - `:private_key` — Private key for signing (falls back to config)

  ## Returns
    - `{:ok, response}` — Result
    - `{:error, term()}` — Error details
  """
  def toggle_spot_dusting(opt_out, opts \\ []) when is_boolean(opt_out) do
    action = %{
      type: "spotUser",
      toggleSpotDusting: %{
        optOut: opt_out
      }
    }

    send_action(action, opts)
  end

  defp send_action(action, opts) do
    private_key = KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

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
