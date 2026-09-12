defmodule Hyperliquid.Api.Exchange.OutcomeDeploy do
  @moduledoc """
  Deploy and settle HIP-4 outcome (prediction) markets.

  ## Shape note (breaking change, Aug 25 2026)

  `outcomeDeploy` used to be nested as a `spotDeploy` variant (`{"type":"spotDeploy",
  "outcome":{...}}` — still what `@nktkas/hyperliquid` v0.33.3 emits). It is now a
  **top-level action** with a **required top-level `venue`** field:

      {"type": "outcomeDeploy", "venue": "<2-4 lowercase letters>", "operation": {...}}

  This module implements the current (top-level) shape only. The nested `spotDeploy`
  variant is deliberately **not** implemented.

  Sub-action functions:

  | Function                                            | `operation` key                                | Purpose                                     |
  |-----------------------------------------------------|------------------------------------------------|---------------------------------------------|
  | `register_standalone_outcome_from_template/3`       | `registerStandaloneOutcomeFromTemplate`        | Deploy a standalone Yes/No market           |
  | `register_question_from_template/3`                 | `registerQuestionFromTemplate`                 | Deploy a question and its named outcomes    |
  | `register_and_associate_named_outcome_from_template/3` | `registerAndAssociateNamedOutcomeFromTemplate` | Add an outcome to a live question        |
  | `settle_outcome/3`                                  | `settleOutcome`                                | Settle one outcome                          |
  | `settle_question2/3`                                | `settleQuestion2`                              | Settle all remaining outcomes of a question |
  | `set_sub_deployers/3`                               | `setSubDeployers`                              | Modify sub-deployer permissions             |

  All variants are L1-signed. Activation/deactivation of the deployer itself lives in
  `Hyperliquid.Api.Exchange.ActivateOutcomeDeployer`.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/hip-4-deployer-actions

  ## Usage

      {:ok, _} = OutcomeDeploy.register_standalone_outcome_from_template("abcd", %{
        id: "template-1",
        keyword_to_value: [["date", "2026-12-31"], ["subject", "BTC"]],
        deployer_fee_scale: "1.0"
      })

      {:ok, _} = OutcomeDeploy.settle_outcome("abcd", %{
        outcome: 95,
        settle_fraction: "1",
        name_and_description: ["Name", "Description"],
        side_names: ["Yes", "No"]
      })
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @venue_regex ~r/^[a-z]{2,4}$/

  @sub_deployer_variants ~w(
    registerStandaloneOutcomeFromTemplate
    registerQuestionFromTemplate
    registerAndAssociateNamedOutcomeFromTemplate
    settleOutcome
    settleQuestion
  )

  @doc """
  Deploy a standalone Yes/No market from a standalone outcome template.

  ## Parameters
    - `venue`: Deployer venue name (2–4 lowercase ASCII letters)
    - `params`: Map with:
      - `:id`                 — Template identifier string
      - `:keyword_to_value`   — List of `["keyword", "value"]` pairs (tuples accepted).
                                Sorted by keyword before emission; values ≤100 chars, no `{`/`}`.
      - `:deployer_fee_scale` — Decimal string in `[0, 10]`
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def register_standalone_outcome_from_template(venue, params, opts \\ []) do
    operation =
      ordered([
        {:registerStandaloneOutcomeFromTemplate, template_instance(params, :with_fee_scale)}
      ])

    send_operation(venue, operation, opts)
  end

  @doc """
  Deploy a question and its named outcomes from templates.

  ## Parameters
    - `venue`: Deployer venue name
    - `params`: Map with:
      - `:question_template_instance`      — Map with `:id`, `:keyword_to_value`, `:deployer_fee_scale`
      - `:named_outcome_template_instances` — List (≤100) of maps with `:id`, `:keyword_to_value`
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def register_question_from_template(venue, params, opts \\ []) do
    instances = Map.fetch!(params, :named_outcome_template_instances)

    if length(instances) > 100 do
      raise ArgumentError, "namedOutcomeTemplateInstances accepts at most 100 entries"
    end

    operation =
      ordered([
        {:registerQuestionFromTemplate,
         ordered([
           {:questionTemplateInstance,
            template_instance(Map.fetch!(params, :question_template_instance), :with_fee_scale)},
           {:namedOutcomeTemplateInstances,
            Enum.map(instances, &template_instance(&1, :no_fee_scale))}
         ])}
      ])

    send_operation(venue, operation, opts)
  end

  @doc """
  Add a named outcome to an already-live question.

  ## Parameters
    - `venue`: Deployer venue name
    - `params`: Map with:
      - `:question`                        — Question index (integer)
      - `:named_outcome_template_instance` — Map with `:id`, `:keyword_to_value`
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def register_and_associate_named_outcome_from_template(venue, params, opts \\ []) do
    operation =
      ordered([
        {:registerAndAssociateNamedOutcomeFromTemplate,
         ordered([
           {:question, Map.fetch!(params, :question)},
           {:namedOutcomeTemplateInstance,
            template_instance(Map.fetch!(params, :named_outcome_template_instance), :no_fee_scale)}
         ])}
      ])

    send_operation(venue, operation, opts)
  end

  @doc """
  Settle a single outcome.

  ## Parameters
    - `venue`: Deployer venue name
    - `params`: Map with:
      - `:outcome`              — Outcome index (integer)
      - `:settle_fraction`      — Yes-side payout fraction, decimal string in `[0, 1]`
      - `:details`              — Optional; must be `""` (the default)
      - `:name_and_description` — `[name, description]` (≤100 / ≤2000 chars)
      - `:side_names`           — `[yes_side_name, no_side_name]`
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def settle_outcome(venue, params, opts \\ []) do
    operation = ordered([{:settleOutcome, outcome_settlement(params)}])
    send_operation(venue, operation, opts)
  end

  @doc """
  Settle all remaining active named outcomes of a question.

  ## Parameters
    - `venue`: Deployer venue name
    - `params`: Map with:
      - `:question`             — Question index (integer)
      - `:outcome_settlements`  — List of `settle_outcome/3`-shaped maps
      - `:name_and_description` — `[name, description]` of the question
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def settle_question2(venue, params, opts \\ []) do
    operation =
      ordered([
        {:settleQuestion2,
         ordered([
           {:question, Map.fetch!(params, :question)},
           {:outcomeSettlements,
            params |> Map.fetch!(:outcome_settlements) |> Enum.map(&outcome_settlement/1)},
           {:nameAndDescription, string_pair(Map.fetch!(params, :name_and_description))}
         ])}
      ])

    send_operation(venue, operation, opts)
  end

  @doc """
  Modify sub-deployer permissions for this venue.

  Note the `setSubDeployers` operation payload is a bare **list**, not an object.

  ## Parameters
    - `venue`: Deployer venue name
    - `sub_deployers`: List of maps with `:variant`, `:user` (address), `:allowed` (bool).
      Valid variants: #{Enum.map_join(@sub_deployer_variants, ", ", &"`#{&1}`")}
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def set_sub_deployers(venue, sub_deployers, opts \\ []) when is_list(sub_deployers) do
    entries =
      Enum.map(sub_deployers, fn sd ->
        variant = Map.fetch!(sd, :variant)

        unless variant in @sub_deployer_variants do
          raise ArgumentError,
                "invalid sub-deployer variant #{inspect(variant)}, expected one of #{inspect(@sub_deployer_variants)}"
        end

        ordered([
          {:variant, variant},
          {:user, Map.fetch!(sd, :user)},
          {:allowed, Map.fetch!(sd, :allowed)}
        ])
      end)

    send_operation(venue, ordered([{:setSubDeployers, entries}]), opts)
  end

  @doc false
  # Exposed for tests: builds the signed action without performing IO.
  def build_action(venue, operation) do
    ordered([
      {:type, "outcomeDeploy"},
      {:venue, validate_venue!(venue)},
      {:operation, operation}
    ])
  end

  # ===================== Builders =====================

  defp template_instance(params, fee_scale_mode) do
    base = [
      {:id, Map.fetch!(params, :id)},
      {:keywordToValue, keyword_to_value(Map.fetch!(params, :keyword_to_value))}
    ]

    case fee_scale_mode do
      :with_fee_scale ->
        ordered(
          base ++
            [{:deployerFeeScale, validate_fee_scale!(Map.fetch!(params, :deployer_fee_scale))}]
        )

      :no_fee_scale ->
        ordered(base)
    end
  end

  defp outcome_settlement(params) do
    details = Map.get(params, :details, "")

    unless details == "" do
      raise ArgumentError, "settlement :details must be the empty string"
    end

    ordered([
      {:outcome, Map.fetch!(params, :outcome)},
      {:settleFraction, validate_settle_fraction!(Map.fetch!(params, :settle_fraction))},
      {:details, details},
      {:nameAndDescription, string_pair(Map.fetch!(params, :name_and_description))},
      {:sideNames, string_pair(Map.fetch!(params, :side_names))}
    ])
  end

  # keywordToValue must be a list of [key, value] pairs sorted by key.
  defp keyword_to_value(pairs) when is_list(pairs) do
    pairs
    |> Enum.map(fn
      {k, v} -> [k, v]
      [k, v] -> [k, v]
    end)
    |> Enum.map(fn [k, v] -> [k, validate_keyword_value!(v)] end)
    |> Enum.sort_by(fn [k, _v] -> k end)
  end

  defp string_pair({a, b}), do: [a, b]
  defp string_pair([a, b]), do: [a, b]

  # ===================== Validation =====================

  defp validate_venue!(venue) when is_binary(venue) do
    if Regex.match?(@venue_regex, venue) do
      venue
    else
      raise ArgumentError,
            "venue must be 2-4 lowercase ASCII letters, got #{inspect(venue)}"
    end
  end

  defp validate_venue!(venue),
    do: raise(ArgumentError, "venue must be a string, got #{inspect(venue)}")

  defp validate_fee_scale!(scale), do: validate_decimal_range!(scale, 0, 10, "deployerFeeScale")

  defp validate_settle_fraction!(fraction),
    do: validate_decimal_range!(fraction, 0, 1, "settleFraction")

  defp validate_decimal_range!(value, min, max, name) do
    value = to_string(value)

    case Float.parse(value) do
      {parsed, ""} when parsed >= min and parsed <= max ->
        value

      _ ->
        raise ArgumentError,
              "#{name} must be a decimal string in [#{min}, #{max}], got #{inspect(value)}"
    end
  end

  defp validate_keyword_value!(value) when is_binary(value) do
    cond do
      String.length(value) > 100 ->
        raise ArgumentError, "keywordToValue values must be at most 100 characters"

      String.contains?(value, ["{", "}"]) ->
        raise ArgumentError, "keywordToValue values must not contain '{' or '}'"

      true ->
        value
    end
  end

  defp validate_keyword_value!(value),
    do: raise(ArgumentError, "keywordToValue values must be strings, got #{inspect(value)}")

  # ===================== Transport =====================

  # IMPORTANT: OrderedObject preserves key order, which the L1 action hash
  # (msgpack over the JSON key order) depends on.
  defp ordered(pairs), do: Jason.OrderedObject.new(pairs)

  defp send_operation(venue, operation, opts) do
    send_action(build_action(venue, operation), opts)
  end

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
