defmodule Hyperliquid.Api.Exchange.BorrowLend do
  @moduledoc """
  Borrow or lend tokens in the Hyperliquid borrow/lend protocol.

  Operations:
  - `"supply"`   — lend tokens into the protocol
  - `"withdraw"` — withdraw a previously supplied position
  - `"repay"`    — repay an outstanding borrow
  - `"borrow"`   — borrow tokens from the protocol

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint

  ## Usage

      # Supply 20 units of token 0
      {:ok, result} = BorrowLend.request("supply", 0, "20")

      # Borrow, using nil to borrow the full available amount
      {:ok, result} = BorrowLend.request("borrow", 0, nil)

      # Repay full balance
      {:ok, result} = BorrowLend.request("repay", 0, nil)
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @valid_operations ["supply", "withdraw", "repay", "borrow"]

  @doc """
  Execute a borrow/lend operation.

  ## Parameters
    - `operation`: One of `"supply"`, `"withdraw"`, `"repay"`, `"borrow"`
    - `token`: Integer token ID
    - `amount`: Amount as a decimal string, or `nil` for the full balance
    - `opts`: Optional parameters

  ## Options
    - `:private_key`   — Private key for signing (falls back to config)
    - `:vault_address` — Act on behalf of a vault

  ## Returns
    - `{:ok, response}` — Result
    - `{:error, term()}` — Error details
  """
  def request(operation, token, amount, opts \\ [])
      when operation in @valid_operations and is_integer(token) do
    private_key = KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "borrowLend",
      operation: operation,
      token: token,
      amount: amount
    }

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
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

  defp generate_nonce, do: Hyperliquid.Utils.generate_nonce()
end
