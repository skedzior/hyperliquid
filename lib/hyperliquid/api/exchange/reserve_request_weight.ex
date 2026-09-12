defmodule Hyperliquid.Api.Exchange.ReserveRequestWeight do
  @moduledoc """
  Reserve additional rate limit capacity.

  Costs 0.0005 USDC per reserved weight unit. Useful for ensuring availability
  of rate limit capacity for critical operations.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http

  @doc """
  Reserve additional rate limit capacity.

  ## Parameters
    - `weight`: Number of weight units to reserve (integer, max 1_844_674_407_370_955)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:destination` - Address of an existing user to reserve the weight **for**.
      Omitted from the action entirely when not supplied.

  ## Returns
    - `{:ok, response}` - Reservation result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = ReserveRequestWeight.request(10)
      {:ok, result} = ReserveRequestWeight.request(10, destination: "0x...")
  """
  def request(weight, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = build_action(weight, Keyword.get(opts, :destination))

    action = Hyperliquid.Api.Exchange.Action.ordered(action)

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <- sign_action(private_key, action_json, nonce, nil, expires_after) do
      Http.exchange_request(action, signature, nonce, nil, expires_after, opts)
    end
  end

  @doc false
  # Exposed for tests: builds the signed action without performing IO.
  # IMPORTANT: OrderedObject pins the key order (type, weight, destination) that the
  # L1 action hash — msgpack over the JSON key order — depends on. `destination` is
  # omitted entirely when nil, since an extra key changes the hash.
  def build_action(weight, destination \\ nil)

  def build_action(weight, nil) do
    Jason.OrderedObject.new([
      {:type, "reserveRequestWeight"},
      {:weight, weight}
    ])
  end

  def build_action(weight, destination) do
    Jason.OrderedObject.new([
      {:type, "reserveRequestWeight"},
      {:weight, weight},
      {:destination, destination}
    ])
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
