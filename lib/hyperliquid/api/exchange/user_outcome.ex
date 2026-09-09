defmodule Hyperliquid.Api.Exchange.UserOutcome do
  @moduledoc """
  Split, merge and negate HIP-4 outcome-market positions.

  L1-signed. The action carries exactly one variant key:

      {"type":"userOutcome","splitOutcome":{"outcome":<uint>,"amount":"<decimal>"}}
      {"type":"userOutcome","mergeOutcome":{"outcome":<uint>,"amount":"<decimal>"|null}}
      {"type":"userOutcome","mergeQuestion":{"question":<uint>,"amount":"<decimal>"|null}}
      {"type":"userOutcome","negateOutcome":{"question":<uint>,"outcome":<uint>,"amount":"<decimal>"}}

  A `nil` amount on `merge_outcome/2` / `merge_question/2` means "merge everything".

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/hip-4-deployer-actions
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @doc """
  Split quote collateral into a complete set of outcome tokens.

  ## Parameters
    - `outcome`: Outcome index (integer)
    - `amount`: Amount as a decimal string
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def split_outcome(outcome, amount, opts \\ []) when is_integer(outcome) do
    build_action(:splitOutcome, [{:outcome, outcome}, {:amount, to_string(amount)}])
    |> send_action(opts)
  end

  @doc """
  Merge a complete set of outcome tokens back into quote collateral.

  ## Parameters
    - `outcome`: Outcome index (integer)
    - `amount`: Amount as a decimal string, or `nil` to merge the full balance
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def merge_outcome(outcome, amount, opts \\ []) when is_integer(outcome) do
    build_action(:mergeOutcome, [{:outcome, outcome}, {:amount, nullable_amount(amount)}])
    |> send_action(opts)
  end

  @doc """
  Merge a complete set of a question's named outcomes back into quote collateral.

  ## Parameters
    - `question`: Question index (integer)
    - `amount`: Amount as a decimal string, or `nil` to merge the full balance
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def merge_question(question, amount, opts \\ []) when is_integer(question) do
    build_action(:mergeQuestion, [{:question, question}, {:amount, nullable_amount(amount)}])
    |> send_action(opts)
  end

  @doc """
  Negate an outcome within a question (convert to the complement set).

  ## Parameters
    - `question`: Question index (integer)
    - `outcome`: Outcome index (integer)
    - `amount`: Amount as a decimal string
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def negate_outcome(question, outcome, amount, opts \\ [])
      when is_integer(question) and is_integer(outcome) do
    build_action(:negateOutcome, [
      {:question, question},
      {:outcome, outcome},
      {:amount, to_string(amount)}
    ])
    |> send_action(opts)
  end

  @doc false
  # Exposed for tests: builds the signed action without performing IO.
  def build_action(variant, fields) do
    # IMPORTANT: OrderedObject preserves key order for the L1 action hash.
    Jason.OrderedObject.new([
      {:type, "userOutcome"},
      {variant, Jason.OrderedObject.new(fields)}
    ])
  end

  defp nullable_amount(nil), do: nil
  defp nullable_amount(amount), do: to_string(amount)

  # ===================== Transport =====================

  defp send_action(action, opts) do
    private_key = KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
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

  defp generate_nonce, do: Hyperliquid.Utils.generate_nonce()
end
