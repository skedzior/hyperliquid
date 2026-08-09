defmodule Hyperliquid.Api.Exchange.UserDexAbstraction do
  @moduledoc """
  Enable or disable DEX abstraction for the calling user.

  This is the exchange-side action for user-initiated DEX abstraction. The
  info-side query lives at `Hyperliquid.Api.Info.UserDexAbstraction`.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint

  ## Usage

      {:ok, result} = UserDexAbstraction.request(true)
      {:ok, result} = UserDexAbstraction.request(false)
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @doc """
  Enable or disable DEX abstraction for the calling user.

  ## Parameters
    - `enabled`: `true` to enable DEX abstraction, `false` to disable
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)

  ## Returns
    - `{:ok, response}` - Result
    - `{:error, term()}` - Error details
  """
  def request(enabled, opts \\ []) do
    private_key = KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "userDexAbstraction",
      enabled: enabled
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

  defp generate_nonce, do: System.system_time(:millisecond)
end
