defmodule Hyperliquid.Api.Exchange.Hip3LiquidatorTransfer do
  @moduledoc """
  Move collateral in or out of a HIP-3 DEX's liquidator account.

  Notional amounts are integers in USDC units as used by the liquidator account.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/hip-3-deployer-actions

  ## Usage

      {:ok, result} = Hip3LiquidatorTransfer.deposit("test", 1_000)
      {:ok, result} = Hip3LiquidatorTransfer.withdraw("test", 500)
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @doc """
  Deposit notional into a HIP-3 DEX's liquidator account.

  ## Parameters
    - `dex`: HIP-3 perp DEX name
    - `ntl`: Notional amount
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` / `{:error, term()}`
  """
  @spec deposit(String.t(), non_neg_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def deposit(dex, ntl, opts \\ []), do: request(dex, ntl, true, opts)

  @doc """
  Withdraw notional from a HIP-3 DEX's liquidator account.

  ## Parameters
    - `dex`: HIP-3 perp DEX name
    - `ntl`: Notional amount
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` / `{:error, term()}`
  """
  @spec withdraw(String.t(), non_neg_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def withdraw(dex, ntl, opts \\ []), do: request(dex, ntl, false, opts)

  @doc """
  Move notional in or out of a HIP-3 DEX's liquidator account.

  ## Parameters
    - `dex`: HIP-3 perp DEX name
    - `ntl`: Notional amount
    - `is_deposit`: true to deposit, false to withdraw
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` / `{:error, term()}`
  """
  @spec request(String.t(), non_neg_integer(), boolean(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def request(dex, ntl, is_deposit, opts \\ [])
      when is_binary(dex) and is_integer(ntl) and is_boolean(is_deposit) do
    if ntl < 0 do
      raise ArgumentError, "ntl must be non-negative, got: #{inspect(ntl)}"
    end

    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "hip3LiquidatorTransfer",
      dex: dex,
      ntl: ntl,
      isDeposit: is_deposit
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
