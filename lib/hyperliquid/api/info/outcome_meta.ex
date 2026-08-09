defmodule Hyperliquid.Api.Info.OutcomeMeta do
  @moduledoc """
  Prediction market (HIP-4) outcome metadata.

  Returns every outcome and question known to the exchange, including the side
  specifications that define each outcome's YES/NO tokens.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/hip-4-deployer-actions

  ## Usage

      {:ok, meta} = OutcomeMeta.request()
      {:ok, outcome} = OutcomeMeta.find_outcome(meta, 7)
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request: %{type: "outcomeMeta"},
    rate_limit_cost: 2,
    doc: "Retrieve prediction market outcome metadata",
    returns: "Outcomes and questions for HIP-4 prediction markets",
    storage: [
      cache: [
        enabled: true,
        ttl: :timer.minutes(5),
        key_pattern: "outcome_meta"
      ]
    ]

  @type t :: %__MODULE__{
          outcomes: [map()],
          questions: [map()]
        }

  @primary_key false
  embedded_schema do
    embeds_many :outcomes, Outcome, primary_key: false do
      @moduledoc "A single prediction market outcome."

      field(:outcome, :integer)
      field(:name, :string)
      field(:description, :string)
      # [%{name: String.t(), token: integer() | nil}]
      field(:side_specs, {:array, :map})
      field(:quote_token, :string)
      # Absent for outcomes not deployed from a template.
      field(:deployer, :string)
    end

    embeds_many :questions, Question, primary_key: false do
      @moduledoc "A prediction market question, the container for named outcomes."

      field(:question, :integer)
      field(:name, :string)
      field(:description, :string)
      field(:fallback_outcome, :integer)
      field(:named_outcomes, {:array, :integer})
      field(:settled_named_outcomes, {:array, :integer})
    end
  end

  # ===================== Changesets =====================

  @doc """
  Creates a changeset for outcome metadata.

  ## Parameters
    - `meta`: The outcome meta struct
    - `attrs`: Map with outcomes and questions keys

  ## Returns
    - `Ecto.Changeset.t()`
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(meta \\ %__MODULE__{}, attrs) do
    meta
    |> cast(attrs, [])
    |> cast_embed(:outcomes, with: &outcome_changeset/2)
    |> cast_embed(:questions, with: &question_changeset/2)
  end

  defp outcome_changeset(outcome, attrs) do
    outcome
    |> cast(attrs, [:outcome, :name, :description, :side_specs, :quote_token, :deployer])
    |> validate_required([:outcome, :name])
  end

  defp question_changeset(question, attrs) do
    question
    |> cast(attrs, [
      :question,
      :name,
      :description,
      :fallback_outcome,
      :named_outcomes,
      :settled_named_outcomes
    ])
    |> validate_required([:question, :name])
  end

  # ===================== Helpers =====================

  @doc """
  Find an outcome by its numeric identifier.

  ## Parameters
    - `meta`: The outcome meta struct
    - `outcome`: Outcome identifier

  ## Returns
    - `{:ok, outcome}` if found
    - `{:error, :not_found}` otherwise
  """
  @spec find_outcome(t(), non_neg_integer()) :: {:ok, map()} | {:error, :not_found}
  def find_outcome(%__MODULE__{outcomes: outcomes}, outcome) when is_integer(outcome) do
    case Enum.find(outcomes, &(&1.outcome == outcome)) do
      nil -> {:error, :not_found}
      found -> {:ok, found}
    end
  end

  @doc """
  Find a question by its numeric identifier.

  ## Parameters
    - `meta`: The outcome meta struct
    - `question`: Question identifier

  ## Returns
    - `{:ok, question}` if found
    - `{:error, :not_found}` otherwise
  """
  @spec find_question(t(), non_neg_integer()) :: {:ok, map()} | {:error, :not_found}
  def find_question(%__MODULE__{questions: questions}, question) when is_integer(question) do
    case Enum.find(questions, &(&1.question == question)) do
      nil -> {:error, :not_found}
      found -> {:ok, found}
    end
  end

  @doc """
  List outcomes deployed by a specific address.

  ## Parameters
    - `meta`: The outcome meta struct
    - `deployer`: Deployer address

  ## Returns
    - List of outcomes deployed by the address
  """
  @spec by_deployer(t(), String.t()) :: [map()]
  def by_deployer(%__MODULE__{outcomes: outcomes}, deployer) when is_binary(deployer) do
    target = String.downcase(deployer)

    Enum.filter(outcomes, fn outcome ->
      is_binary(outcome.deployer) and String.downcase(outcome.deployer) == target
    end)
  end

  @doc """
  Check whether a question has fully settled — every named outcome is settled.

  ## Parameters
    - `question`: A question from the metadata

  ## Returns
    - `boolean()`
  """
  @spec question_settled?(map()) :: boolean()
  def question_settled?(%{named_outcomes: named, settled_named_outcomes: settled})
      when is_list(named) and is_list(settled) do
    named != [] and MapSet.subset?(MapSet.new(named), MapSet.new(settled))
  end

  def question_settled?(_), do: false
end
