defmodule Hyperliquid.Api.Exchange.CancelByCloid do
  @moduledoc """
  Cancel orders on Hyperliquid by client order ID.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  # ===================== Types =====================

  @type cancel_request :: %{
          asset: non_neg_integer(),
          cloid: String.t()
        }

  @type cancel_opts :: [
          vault_address: String.t()
        ]

  @type cancel_response :: %{
          status: String.t(),
          response: %{
            type: String.t(),
            data: %{
              statuses: list()
            }
          }
        }

  # ===================== Request Functions =====================

  @doc """
  Cancel a single order by client order ID.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `asset`: Asset index
    - `cloid`: Client order ID to cancel
    - `opts`: Optional parameters

  ## Options
    - `:vault_address` - Cancel on behalf of a vault

  ## Returns
    - `{:ok, response}` - Cancel result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = CancelByCloid.cancel(private_key, 0, "my-order-1")
  """
  @spec cancel(non_neg_integer(), String.t(), cancel_opts()) ::
          {:ok, cancel_response()} | {:error, term()}
  def cancel(asset, cloid, opts \\ []) do
    cancel_batch([%{asset: asset, cloid: cloid}], opts)
  end

  @doc """
  Cancel multiple orders by client order ID.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `cancels`: List of cancel requests `[%{asset: 0, cloid: "id"}, ...]`
    - `opts`: Optional parameters

  ## Options
    - `:vault_address` - Cancel on behalf of a vault

  ## Returns
    - `{:ok, response}` - Batch cancel result
    - `{:error, term()}` - Error details

  ## Examples

      cancels = [
        %{asset: 0, cloid: "my-order-1"},
        %{asset: 0, cloid: "my-order-2"}
      ]
      {:ok, result} = CancelByCloid.cancel_batch(private_key, cancels)
  """
  @spec cancel_batch([cancel_request()], cancel_opts()) ::
          {:ok, cancel_response()} | {:error, term()}
  def cancel_batch(cancels, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)

    action = build_action(cancels)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after),
         {:ok, response} <-
           Http.exchange_request(action, signature, nonce, vault_address, expires_after) do
      {:ok, response}
    end
  end

  # ===================== Action Building =====================

  defp build_action(cancels) do
    %{
      type: "cancelByCloid",
      cancels:
        Enum.map(cancels, fn c ->
          %{
            asset: c.asset,
            cloid: c.cloid
          }
        end)
    }
  end

  # ===================== Signing =====================

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

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
