defmodule Hyperliquid.Api.Exchange.Hip3LiquidatorTransfer do
  @moduledoc """
  Deposit to or withdraw from a HIP-3 DEX liquidator account.

  L1-signed.

      {"type":"hip3LiquidatorTransfer","dex":"<dex>","ntl":<uint>,"isDeposit":<bool>}

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @doc """
  Transfer notional to or from a HIP-3 liquidator account.

  ## Parameters
    - `dex`: DEX name string
    - `ntl`: Notional amount (integer, USDC with 6 decimals implied by the API)
    - `is_deposit`: `true` to deposit into the liquidator account, `false` to withdraw
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def request(dex, ntl, is_deposit, opts \\ [])
      when is_binary(dex) and is_integer(ntl) and is_boolean(is_deposit) do
    if ntl < 0 do
      raise ArgumentError, "ntl must be non-negative, got: #{inspect(ntl)}"
    end

    send_action(build_action(dex, ntl, is_deposit), opts)
  end

  @doc """
  Deposit notional into a HIP-3 DEX liquidator account.
  """
  @spec deposit(String.t(), non_neg_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def deposit(dex, ntl, opts \\ []), do: request(dex, ntl, true, opts)

  @doc """
  Withdraw notional from a HIP-3 DEX liquidator account.
  """
  @spec withdraw(String.t(), non_neg_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def withdraw(dex, ntl, opts \\ []), do: request(dex, ntl, false, opts)

  @doc false
  # Exposed for tests: builds the signed action without performing IO.
  # IMPORTANT: OrderedObject preserves key order for the L1 action hash.
  def build_action(dex, ntl, is_deposit) do
    Jason.OrderedObject.new([
      {:type, "hip3LiquidatorTransfer"},
      {:dex, dex},
      {:ntl, ntl},
      {:isDeposit, is_deposit}
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
