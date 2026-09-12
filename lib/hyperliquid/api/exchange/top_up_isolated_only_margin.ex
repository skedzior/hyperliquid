defmodule Hyperliquid.Api.Exchange.TopUpIsolatedOnlyMargin do
  @moduledoc """
  Top up the margin of an isolated-only position back to a target leverage.

  L1-signed. Supports `:vault_address`.

      {"type":"topUpIsolatedOnlyMargin","asset":<uint>,"leverage":"<decimal>"}

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @doc """
  Top up isolated-only margin for an asset.

  ## Parameters
    - `asset`: Asset index (integer)
    - `leverage`: Target leverage as a decimal string (e.g. `"3"`)
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def request(asset, leverage, opts \\ []) when is_integer(asset) do
    send_action(build_action(asset, to_string(leverage)), opts)
  end

  @doc false
  # Exposed for tests: builds the signed action without performing IO.
  # IMPORTANT: OrderedObject preserves key order for the L1 action hash.
  def build_action(asset, leverage) do
    Jason.OrderedObject.new([
      {:type, "topUpIsolatedOnlyMargin"},
      {:asset, asset},
      {:leverage, leverage}
    ])
  end

  defp send_action(action, opts) do
    private_key = KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = Hyperliquid.Utils.generate_nonce()
    expires_after = Config.expires_after()

    action = Hyperliquid.Api.Exchange.Action.ordered(action)

    with {:ok, action_json} <- Jason.encode(action),
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
end
