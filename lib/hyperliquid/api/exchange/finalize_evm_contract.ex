defmodule Hyperliquid.Api.Exchange.FinalizeEvmContract do
  @moduledoc """
  Link a HyperCore token to its deployed HyperEVM contract.

  The verification method must match how the contract was deployed:

  - `finalize_with_create/3` — contract deployed from an EOA; the EVM user signs
    with the nonce used for the deployment
  - `finalize_with_first_storage_slot/2` — the finalizer address is stored at the
    contract's first storage slot
  - `finalize_with_custom_storage_slot/2` — the finalizer address is stored at
    slot `keccak256("HyperCore deployer")`

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore

  ## Usage

      {:ok, result} = FinalizeEvmContract.finalize_with_create(42, 7)
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @doc """
  Finalize a contract deployed from an EOA using its deployment nonce.

  ## Parameters
    - `token`: Token identifier to link
    - `deploy_nonce`: Nonce used to deploy the EVM contract
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` / `{:error, term()}`

  ## Examples

      {:ok, result} = FinalizeEvmContract.finalize_with_create(42, 7)
  """
  @spec finalize_with_create(non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def finalize_with_create(token, deploy_nonce, opts \\ [])
      when is_integer(token) and is_integer(deploy_nonce) do
    request(token, %{create: %{nonce: deploy_nonce}}, opts)
  end

  @doc """
  Finalize a contract that stores the finalizer address in its first storage slot.

  ## Parameters
    - `token`: Token identifier to link
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` / `{:error, term()}`
  """
  @spec finalize_with_first_storage_slot(non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def finalize_with_first_storage_slot(token, opts \\ []) when is_integer(token) do
    request(token, "firstStorageSlot", opts)
  end

  @doc """
  Finalize a contract that stores the finalizer address at
  `keccak256("HyperCore deployer")`.

  ## Parameters
    - `token`: Token identifier to link
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` / `{:error, term()}`
  """
  @spec finalize_with_custom_storage_slot(non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def finalize_with_custom_storage_slot(token, opts \\ []) when is_integer(token) do
    request(token, "customStorageSlot", opts)
  end

  defp request(token, input, opts) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "finalizeEvmContract",
      token: token,
      input: input
    }

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after) do
      Http.exchange_request(action, signature, nonce, vault_address, expires_after, opts)
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
