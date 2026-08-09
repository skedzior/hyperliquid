defmodule Hyperliquid.Api.Exchange.CValidatorAction do
  @moduledoc """
  Perform validator management actions.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @doc """
  Perform validator management actions.

  ## Parameters
    - `private_key`: Private key for signing (hex string)
    - `action_type`: Type of action (:delegate, :undelegate, :change_signer, :edit_validator)
    - `params`: Action-specific parameters
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` - Action result
    - `{:error, term()}` - Error details

  ## Examples

      # Delegate to validator
      {:ok, result} = CValidatorAction.request(private_key, :delegate,
        validator: "0x...",
        wei: 100_000_000
      )

      # Undelegate from validator
      {:ok, result} = CValidatorAction.request(private_key, :undelegate,
        validator: "0x...",
        wei: 100_000_000
      )
  """
  def request(action_type, params, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    inner_action = build_inner_action(action_type, params)

    action = %{
      type: "cValidatorAction",
      action: inner_action
    }

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <- sign_action(private_key, action_json, nonce, nil, expires_after) do
      Http.exchange_request(action, signature, nonce, nil, expires_after, opts)
    end
  end

  defp build_inner_action(:delegate, params) do
    %{
      type: "delegate",
      validator: Keyword.fetch!(params, :validator),
      wei: Keyword.fetch!(params, :wei)
    }
  end

  defp build_inner_action(:undelegate, params) do
    %{
      type: "undelegate",
      validator: Keyword.fetch!(params, :validator),
      wei: Keyword.fetch!(params, :wei)
    }
  end

  defp build_inner_action(:change_signer, params) do
    %{
      type: "changeSigner",
      newSigner: Keyword.fetch!(params, :new_signer)
    }
  end

  defp build_inner_action(:edit_validator, params) do
    action = %{type: "editValidator"}

    action
    |> maybe_put(:name, Keyword.get(params, :name))
    |> maybe_put(:description, Keyword.get(params, :description))
    |> maybe_put(:commissionBps, Keyword.get(params, :commission_bps))
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
