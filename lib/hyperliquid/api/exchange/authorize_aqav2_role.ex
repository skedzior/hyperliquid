defmodule Hyperliquid.Api.Exchange.AuthorizeAqav2Role do
  @moduledoc """
  Authorize an AQAv2 role for a token.

  L1-signed.

      {"type":"authorizeAqav2Role","token":<uint>,"role":"technical"|"treasury"}

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @roles ~w(technical treasury)

  @doc """
  Authorize an AQAv2 role for a token.

  ## Parameters
    - `token`: Token index (integer)
    - `role`: `"technical"` or `"treasury"`
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def request(token, role, opts \\ []) when is_integer(token) do
    role = to_string(role)

    unless role in @roles do
      raise ArgumentError, "role must be :technical or :treasury, got: #{inspect(role)}"
    end

    send_action(build_action(token, role), opts)
  end

  @doc """
  Valid role names.
  """
  @spec roles() :: [String.t()]
  def roles, do: @roles

  @doc false
  # Exposed for tests: builds the signed action without performing IO.
  # IMPORTANT: OrderedObject preserves key order for the L1 action hash.
  def build_action(token, role) do
    Jason.OrderedObject.new([
      {:type, "authorizeAqav2Role"},
      {:token, token},
      {:role, role}
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
