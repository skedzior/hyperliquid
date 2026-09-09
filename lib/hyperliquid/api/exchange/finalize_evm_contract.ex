defmodule Hyperliquid.Api.Exchange.FinalizeEvmContract do
  @moduledoc """
  Finalize the link between a HyperCore spot token and a HyperEVM ERC-20 contract.

  Sent by the **EVM deployer**; the link is first requested by the spot deployer via
  the `spotDeploy.requestEvmContract` variant. L1-signed.

      {"type":"finalizeEvmContract","token":<uint>,"input":{"create":{"nonce":<uint>}}}
      {"type":"finalizeEvmContract","token":<uint>,"input":"firstStorageSlot"}
      {"type":"finalizeEvmContract","token":<uint>,"input":"customStorageSlot"}

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/hypercore-less-than-greater-than-hyperevm-transfers
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @doc """
  Finalize an EVM contract link.

  ## Parameters
    - `token`: Token index (integer)
    - `input`: One of
      - `{:create, nonce}` (or `%{create: %{nonce: nonce}}`) — verify via the deploy nonce
      - `:first_storage_slot` / `"firstStorageSlot"`
      - `:custom_storage_slot` / `"customStorageSlot"`
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def request(token, input, opts \\ []) when is_integer(token) do
    send_action(build_action(token, input), opts)
  end

  @doc """
  Finalize a contract deployed from an EOA, using its deployment nonce.
  """
  @spec finalize_with_create(non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def finalize_with_create(token, deploy_nonce, opts \\ [])
      when is_integer(token) and is_integer(deploy_nonce) do
    request(token, %{create: %{nonce: deploy_nonce}}, opts)
  end

  @doc """
  Finalize a contract that stores the finalizer address in its first storage slot.
  """
  @spec finalize_with_first_storage_slot(non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def finalize_with_first_storage_slot(token, opts \\ []) when is_integer(token) do
    request(token, "firstStorageSlot", opts)
  end

  @doc """
  Finalize a contract that stores the finalizer address at
  `keccak256("HyperCore deployer")`.
  """
  @spec finalize_with_custom_storage_slot(non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def finalize_with_custom_storage_slot(token, opts \\ []) when is_integer(token) do
    request(token, "customStorageSlot", opts)
  end

  @doc false
  # Exposed for tests: builds the signed action without performing IO.
  # IMPORTANT: OrderedObject preserves key order for the L1 action hash.
  def build_action(token, input) do
    Jason.OrderedObject.new([
      {:type, "finalizeEvmContract"},
      {:token, token},
      {:input, format_input(input)}
    ])
  end

  defp format_input({:create, nonce}) when is_integer(nonce) do
    Jason.OrderedObject.new([
      {:create, Jason.OrderedObject.new([{:nonce, nonce}])}
    ])
  end

  defp format_input(%{create: %{nonce: nonce}}), do: format_input({:create, nonce})
  defp format_input(:first_storage_slot), do: "firstStorageSlot"
  defp format_input(:custom_storage_slot), do: "customStorageSlot"
  defp format_input("firstStorageSlot"), do: "firstStorageSlot"
  defp format_input("customStorageSlot"), do: "customStorageSlot"

  defp format_input(other),
    do:
      raise(
        ArgumentError,
        "input must be {:create, nonce}, :first_storage_slot or :custom_storage_slot, got #{inspect(other)}"
      )

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
