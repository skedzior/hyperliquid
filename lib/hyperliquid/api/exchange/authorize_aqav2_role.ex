defmodule Hyperliquid.Api.Exchange.AuthorizeAqav2Role do
  @moduledoc """
  Authorize the signing account for an AQAV2 role on a token.

  Two roles exist: `:technical` and `:treasury`.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint

  ## Usage

      {:ok, result} = AuthorizeAqav2Role.request(42, :technical)
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @roles %{technical: "technical", treasury: "treasury"}

  @type role :: :technical | :treasury

  @doc """
  Authorize an AQAV2 role on a token.

  ## Parameters
    - `token`: Token identifier
    - `role`: `:technical` or `:treasury` (the strings are also accepted)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:vault_address` - Act on behalf of a vault

  ## Returns
    - `{:ok, response}` - Authorization result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = AuthorizeAqav2Role.request(42, :treasury)
  """
  @spec request(non_neg_integer(), role() | String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def request(token, role, opts \\ []) when is_integer(token) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "authorizeAqav2Role",
      token: token,
      role: normalize_role!(role)
    }

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after) do
      Http.exchange_request(action, signature, nonce, vault_address, expires_after, opts)
    end
  end

  @doc """
  Valid role names.

  ## Returns
    - List of role strings
  """
  @spec roles() :: [String.t()]
  def roles, do: Map.values(@roles)

  defp normalize_role!(role) when is_atom(role) do
    case Map.fetch(@roles, role) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "role must be :technical or :treasury, got: #{inspect(role)}"
    end
  end

  defp normalize_role!(role) when is_binary(role) do
    if role in Map.values(@roles) do
      role
    else
      raise ArgumentError, "role must be :technical or :treasury, got: #{inspect(role)}"
    end
  end

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
