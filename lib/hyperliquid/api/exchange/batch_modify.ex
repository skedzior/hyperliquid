defmodule Hyperliquid.Api.Exchange.BatchModify do
  @moduledoc """
  Modify multiple existing orders in a batch on Hyperliquid.

  For modifying a single order, use `Hyperliquid.Api.Exchange.Modify`.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint#modify-multiple-orders
  """

  require Logger

  alias Hyperliquid.{Config, Utils}
  alias Hyperliquid.Api.Exchange.Order
  alias Hyperliquid.Transport.Http

  # ===================== Types =====================

  @type modify_request :: %{
          oid: non_neg_integer(),
          order: Order.order()
        }

  @type modify_opts :: [
          vault_address: String.t()
        ]

  @type modify_response :: %{
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
  Modify multiple orders in a batch.

  ## Parameters
    - `modifies`: List of modify requests `[%{oid: 123, order: order}, ...]`
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:vault_address` - Modify on behalf of a vault

  ## Returns
    - `{:ok, response}` - Batch modify result
    - `{:error, term()}` - Error details

  ## Examples

      modifies = [
        %{oid: 12345, order: Order.limit(0, true, "51000.0", "0.1")},
        %{oid: 12346, order: Order.limit(0, true, "52000.0", "0.1")}
      ]
      {:ok, result} = BatchModify.modify_batch(modifies)

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  @spec modify_batch([modify_request()], modify_opts()) ::
          {:ok, modify_response()} | {:error, term()}
  def modify_batch(modifies, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)

    action = build_action(modifies)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    debug("modify_batch called", %{
      modifies_count: length(modifies),
      vault_address: vault_address,
      nonce: nonce
    })

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         _ <- debug("Action encoded", %{action: action}),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after),
         _ <- debug("Action signed", %{signature: signature}),
         {:ok, response} <-
           Http.exchange_request(action, signature, nonce, vault_address, expires_after) do
      debug("Response received", %{response: response})
      {:ok, response}
    else
      {:error, reason} = error ->
        debug("Error occurred", %{error: reason})
        error
    end
  end

  # ===================== Action Building =====================

  defp build_action(modifies) do
    # IMPORTANT: Entire action structure must use OrderedObject for correct hash!
    # Field order: type, modifies
    Jason.OrderedObject.new([
      {:type, "batchModify"},
      {:modifies,
       Enum.map(modifies, fn m ->
         # Each modify item must also be OrderedObject
         # Field order: oid, order
         Jason.OrderedObject.new([
           {:oid, m.oid},
           {:order, format_order(m.order)}
         ])
       end)}
    ])
  end

  defp format_order(%{order_type: :limit} = order) do
    # IMPORTANT: Field order matters for hash calculation!
    # Must match TypeScript order: a, b, p, s, r, t, c (optional)
    base = [
      {:a, order.asset},
      {:b, order.is_buy},
      {:p, Utils.float_to_string(order.limit_px)},
      {:s, Utils.float_to_string(order.sz)},
      {:r, order.reduce_only},
      {:t,
       Jason.OrderedObject.new([
         {:limit,
          Jason.OrderedObject.new([
            {:tif, order.tif}
          ])}
       ])}
    ]

    base
    |> maybe_add_cloid(order.cloid)
    |> Jason.OrderedObject.new()
  end

  defp format_order(%{order_type: :trigger} = order) do
    # IMPORTANT: Field order matters for hash calculation!
    # Must match TypeScript order: a, b, p, s, r, t, c (optional)
    base = [
      {:a, order.asset},
      {:b, order.is_buy},
      {:p, Utils.float_to_string(order.limit_px)},
      {:s, Utils.float_to_string(order.sz)},
      {:r, order.reduce_only},
      {:t,
       Jason.OrderedObject.new([
         {:trigger,
          Jason.OrderedObject.new([
            {:isMarket, order.is_market},
            {:triggerPx, Utils.float_to_string(order.trigger_px)},
            {:tpsl, order.tpsl}
          ])}
       ])}
    ]

    base
    |> maybe_add_cloid(order.cloid)
    |> Jason.OrderedObject.new()
  end

  defp maybe_add_cloid(fields, nil), do: fields
  defp maybe_add_cloid(fields, cloid), do: fields ++ [{:c, cloid}]

  # ===================== Signing =====================

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

  defp debug(message, data) do
    if Config.debug?() do
      Logger.debug("[BatchModify] #{message}", data: data)
    end

    :ok
  end
end
