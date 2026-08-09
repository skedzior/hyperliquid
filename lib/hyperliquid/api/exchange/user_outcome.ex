defmodule Hyperliquid.Api.Exchange.UserOutcome do
  @moduledoc """
  Split, merge and negate HIP-4 prediction market outcome positions.

  The four variants are:

  - `split_outcome/3` - mint one YES and one NO token of an outcome by locking
    collateral
  - `merge_outcome/3` - burn matched YES/NO pairs of an outcome back into
    collateral
  - `merge_question/3` - burn one token of every named outcome of a question back
    into collateral
  - `negate_outcome/4` - convert a named outcome's NO token into the remaining
    named outcomes of its question

  Amounts are decimal strings. A `nil` amount on the merge variants means "as
  much as possible".

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/hip-4-deployer-actions
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @doc """
  Mint one YES and one NO token of `outcome` by locking collateral.

  ## Parameters
    - `outcome`: Outcome identifier
    - `amount`: Amount as a decimal string
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` / `{:error, term()}`

  ## Examples

      {:ok, result} = UserOutcome.split_outcome(7, "1")
  """
  @spec split_outcome(non_neg_integer(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def split_outcome(outcome, amount, opts \\ []) when is_integer(outcome) do
    request(%{splitOutcome: %{outcome: outcome, amount: to_amount(amount)}}, opts)
  end

  @doc """
  Burn matched YES/NO pairs of `outcome` back into collateral.

  ## Parameters
    - `outcome`: Outcome identifier
    - `amount`: Amount as a decimal string, or `nil` for the maximum available
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` / `{:error, term()}`

  ## Examples

      {:ok, result} = UserOutcome.merge_outcome(7, "0.5")
      {:ok, result} = UserOutcome.merge_outcome(7, nil)
  """
  @spec merge_outcome(non_neg_integer(), String.t() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def merge_outcome(outcome, amount \\ nil, opts \\ []) when is_integer(outcome) do
    request(%{mergeOutcome: %{outcome: outcome, amount: to_amount(amount)}}, opts)
  end

  @doc """
  Burn one token of every named outcome of `question` back into collateral.

  ## Parameters
    - `question`: Question identifier
    - `amount`: Amount as a decimal string, or `nil` for the maximum available
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` / `{:error, term()}`

  ## Examples

      {:ok, result} = UserOutcome.merge_question(3, "1")
  """
  @spec merge_question(non_neg_integer(), String.t() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def merge_question(question, amount \\ nil, opts \\ []) when is_integer(question) do
    request(%{mergeQuestion: %{question: question, amount: to_amount(amount)}}, opts)
  end

  @doc """
  Convert a named outcome's NO token into the remaining named outcomes of its
  question.

  ## Parameters
    - `question`: Question identifier
    - `outcome`: Named outcome identifier within that question
    - `amount`: Amount as a decimal string
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` / `{:error, term()}`

  ## Examples

      {:ok, result} = UserOutcome.negate_outcome(3, 7, "1")
  """
  @spec negate_outcome(non_neg_integer(), non_neg_integer(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def negate_outcome(question, outcome, amount, opts \\ [])
      when is_integer(question) and is_integer(outcome) do
    request(
      %{negateOutcome: %{question: question, outcome: outcome, amount: to_amount(amount)}},
      opts
    )
  end

  # ===================== Internal =====================

  defp to_amount(nil), do: nil
  defp to_amount(amount) when is_binary(amount), do: amount
  defp to_amount(amount) when is_integer(amount), do: Integer.to_string(amount)
  defp to_amount(amount) when is_float(amount), do: Hyperliquid.Utils.float_to_string(amount)

  defp request(variant, opts) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = Map.merge(%{type: "userOutcome"}, variant)

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
