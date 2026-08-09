defmodule Hyperliquid.Api.Exchange.VaultModify do
  @moduledoc """
  Create or modify a vault.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @doc """
  Create or modify a vault.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `opts`: Vault options

  ## Options (for creation)
    - `:name` - Vault name
    - `:description` - Vault description
    - `:portfolio_manager_cut_bps` - Manager fee in basis points (1 bp = 0.01%)
    - `:allow_deposits` - Allow deposits (default: true)

  ## Options (for modification)
    - `:vault_address` - Address of vault to modify

  ## Returns
    - `{:ok, response}` - Result with vault address
    - `{:error, term()}` - Error details

  ## Examples

      # Create new vault
      {:ok, result} = VaultModify.request(private_key,
        name: "My Vault",
        description: "Trading strategy",
        portfolio_manager_cut_bps: 500  # 5%
      )

      # Modify existing vault
      {:ok, result} = VaultModify.request(private_key,
        vault_address: "0x...",
        allow_deposits: false
      )
  """
  def request(opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    # Build vault config
    config =
      %{}
      |> maybe_put(:name, Keyword.get(opts, :name))
      |> maybe_put(:description, Keyword.get(opts, :description))
      |> maybe_put(:portfolioManagerCutBps, Keyword.get(opts, :portfolio_manager_cut_bps))
      |> maybe_put(:allowDeposits, Keyword.get(opts, :allow_deposits))

    action =
      if vault_address do
        %{
          type: "vaultModify",
          vaultAddress: vault_address,
          config: config
        }
      else
        %{
          type: "vaultModify",
          config: config
        }
      end

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <- sign_action(private_key, action_json, nonce, nil, expires_after) do
      Http.exchange_request(action, signature, nonce, nil, expires_after, opts)
    end
  end

  defp sign_action(private_key, action_json, nonce, vault_address, expires_after) do
    is_mainnet = Config.mainnet?()

    connection_id =
      Signer.compute_connection_id_ex(action_json, nonce, vault_address, expires_after)

    case Signer.sign_l1_action(private_key, connection_id, is_mainnet) do
      %{"r" => r, "s" => s, "v" => v} ->
        {:ok, %{r: r, s: s, v: v}}

      error ->
        {:error, {:signing_error, error}}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
