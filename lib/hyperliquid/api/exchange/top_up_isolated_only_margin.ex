defmodule Hyperliquid.Api.Exchange.TopUpIsolatedOnlyMargin do
  @moduledoc """
  Top up an isolated-only position's margin back to a target leverage.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint

  ## Usage

      {:ok, result} = TopUpIsolatedOnlyMargin.request(3, "5")
  """

  alias Hyperliquid.{Config, Signer, Utils}
  alias Hyperliquid.Transport.Http

  @doc """
  Top up isolated-only margin for an asset.

  ## Parameters
    - `asset`: Asset index
    - `leverage`: Target leverage as a decimal string (numbers are converted)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:vault_address` - Act on behalf of a vault

  ## Returns
    - `{:ok, response}` - Result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = TopUpIsolatedOnlyMargin.request(3, "5")
  """
  @spec request(non_neg_integer(), String.t() | number(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def request(asset, leverage, opts \\ []) when is_integer(asset) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "topUpIsolatedOnlyMargin",
      asset: asset,
      leverage: to_decimal_string(leverage)
    }

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after) do
      Http.exchange_request(action, signature, nonce, vault_address, expires_after, opts)
    end
  end

  defp to_decimal_string(value) when is_binary(value), do: value
  defp to_decimal_string(value) when is_integer(value), do: Integer.to_string(value)
  defp to_decimal_string(value) when is_float(value), do: Utils.float_to_string(value)

  defp sign_action(private_key, action_json, nonce, vault_address, expires_after) do
    is_mainnet = Config.mainnet?()

    connection_id =
      Signer.compute_connection_id_ex(action_json, nonce, vault_address, expires_after)

    case Signer.sign_l1_action(private_key, connection_id, is_mainnet) do
      %{"r" => r, "s" => s, "v" => v} -> {:ok, %{r: r, s: s, v: v}}
      error -> {:error, {:signing_error, error}}
    end
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
