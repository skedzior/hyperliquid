defmodule Hyperliquid.Api.Exchange.Cancel do
  @moduledoc """
  Cancel orders on Hyperliquid by order ID.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  # ===================== Types =====================

  @type cancel_request :: %{
          asset: non_neg_integer(),
          oid: non_neg_integer()
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
  Cancel a single order by order ID.

  ## Parameters
    - `asset`: Asset index
    - `oid`: Order ID to cancel
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:vault_address` - Cancel on behalf of a vault

  ## Returns
    - `{:ok, response}` - Cancel result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = Cancel.cancel(0, 12345)

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  @spec cancel(non_neg_integer(), non_neg_integer(), cancel_opts()) ::
          {:ok, cancel_response()} | {:error, term()}
  def cancel(asset, oid, opts \\ []) do
    cancel_batch([%{asset: asset, oid: oid}], opts)
  end

  @doc """
  Cancel multiple orders by order ID.

  ## Parameters
    - `cancels`: List of cancel requests `[%{asset: 0, oid: 123}, ...]`
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:vault_address` - Cancel on behalf of a vault

  ## Returns
    - `{:ok, response}` - Batch cancel result
    - `{:error, term()}` - Error details

  ## Examples

      cancels = [
        %{asset: 0, oid: 12345},
        %{asset: 0, oid: 12346}
      ]
      {:ok, result} = Cancel.cancel_batch(cancels)

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
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
      type: "cancel",
      cancels:
        Enum.map(cancels, fn c ->
          %{
            a: c.asset,
            o: c.oid
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
