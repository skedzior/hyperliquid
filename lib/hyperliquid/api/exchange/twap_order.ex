defmodule Hyperliquid.Api.Exchange.TwapOrder do
  @moduledoc """
  Place a TWAP (Time-Weighted Average Price) order.

  TWAP orders split large orders into smaller chunks executed over time.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Utils}
  alias Hyperliquid.Transport.Http

  @doc """
  Place a TWAP order.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `asset`: Asset index
    - `is_buy`: true for buy, false for sell
    - `sz`: Total size
    - `opts`: Order options

  ## Options
    - `:reduce_only` - Only reduce position (default: false)
    - `:duration_minutes` - Duration in minutes (default: 5)
    - `:randomize` - Randomize execution (default: false)
    - `:vault_address` - Trade for a vault
    - `:details` - Optional trigger / stop configuration. Map with:
      - `:trigger` - `%{px: "<decimal>", above: boolean}` or `nil` — activates the TWAP
        when the mark price crosses `px` from below (`above: true`) or above (`above: false`)
      - `:stop_px` - `"<decimal>"` or `nil` — price at which the TWAP is terminated

      Emitted as `{"t": {"p": px, "a": above} | null, "s": stopPx | null}` appended after
      `twap`. The key is omitted entirely when `:details` is absent — adding it changes the
      L1 action hash.

  ## Returns
    - `{:ok, response}` - Order result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = TwapOrder.request(0, true, "1.0", duration_minutes: 30)

      # Trigger at 50000 (mark price rising through it), stop at 45000
      {:ok, result} = TwapOrder.request(0, true, "1.0",
        details: %{trigger: %{px: "50000", above: true}, stop_px: "45000"})
  """
  def request(asset, is_buy, sz, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    # IMPORTANT: Use OrderedObject for correct field order in hash calculation
    # Twap field order: a, b, s, r, m, t
    twap =
      Jason.OrderedObject.new([
        {:a, asset},
        {:b, is_buy},
        {:s, Utils.float_to_string(sz)},
        {:r, Keyword.get(opts, :reduce_only, false)},
        {:m, Keyword.get(opts, :duration_minutes, 5)},
        {:t, Keyword.get(opts, :randomize, false)}
      ])

    # Action field order: type, twap, details (details omitted when not supplied)
    action = build_action(twap, Keyword.get(opts, :details))

    action = Hyperliquid.Api.Exchange.Action.ordered(action)

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after) do
      Http.exchange_request(action, signature, nonce, vault_address, expires_after, opts)
    end
  end

  @doc false
  # Exposed for tests: builds the signed action without performing IO.
  # IMPORTANT: OrderedObject pins the key order the L1 action hash depends on.
  def build_action(twap, details \\ nil)

  def build_action(twap, nil) do
    Jason.OrderedObject.new([
      {:type, "twapOrder"},
      {:twap, twap}
    ])
  end

  def build_action(twap, details) do
    Jason.OrderedObject.new([
      {:type, "twapOrder"},
      {:twap, twap},
      {:details, build_details(details)}
    ])
  end

  # details field order: t (trigger), s (stop price)
  defp build_details(details) do
    Jason.OrderedObject.new([
      {:t, build_trigger(Map.get(details, :trigger))},
      {:s, format_optional_px(Map.get(details, :stop_px))}
    ])
  end

  defp build_trigger(nil), do: nil

  defp build_trigger(trigger) do
    # trigger field order: p (price), a (above)
    Jason.OrderedObject.new([
      {:p, Utils.float_to_string(Map.fetch!(trigger, :px))},
      {:a, Map.fetch!(trigger, :above)}
    ])
  end

  defp format_optional_px(nil), do: nil
  defp format_optional_px(px), do: Utils.float_to_string(px)

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
