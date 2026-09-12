defmodule Hyperliquid.Api.Exchange.ScheduleCancel do
  @moduledoc """
  Schedule all open orders to be cancelled at a specified time.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http

  @doc """
  Schedule all open orders to be cancelled at a specified time.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `time`: Unix timestamp in milliseconds when to cancel orders (or nil to remove scheduled cancel)
    - `opts`: Optional parameters

  ## Options
    - `:vault_address` - Schedule for a vault

  ## Returns
    - `{:ok, response}` - Schedule result
    - `{:error, term()}` - Error details

  ## Examples

      # Schedule cancel in 1 hour
      {:ok, result} = ScheduleCancel.request(private_key, System.system_time(:millisecond) + 3600000)

      # Remove scheduled cancel
      {:ok, result} = ScheduleCancel.request(private_key, nil)
  """
  def request(time, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    # IMPORTANT: Use OrderedObject for correct field order in hash calculation
    # Field order: type, time (optional - can be nil to remove scheduled cancel)
    action_fields = [{:type, "scheduleCancel"}]

    action_fields =
      if time != nil do
        action_fields ++ [{:time, time}]
      else
        action_fields
      end

    action = Jason.OrderedObject.new(action_fields)

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after) do
      Http.exchange_request(action, signature, nonce, vault_address, expires_after, opts)
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
