defmodule Hyperliquid.Api.Info.ValidatorL1Votes do
  @moduledoc """
  Validator L1 votes.

  Returns L1 voting information for validators.

  ## Vote payloads

  A vote arrives either as a plain string or as a single-key object naming the
  variant. Both are preserved: `vote` always holds the variant name (or the raw
  string) and `vote_data` holds the structured payload when there is one.

  > Note: the HTTP transport snake_cases every response key, so the variant name
  > reaching `vote` is `"register_template"` / `"settle_question2"` rather than the
  > camelCase spelling used in the upstream TypeScript types below.

  Two HIP-4 variants were added upstream (`@nktkas/hyperliquid` `2f89085`) and are
  passed through untyped rather than modelled:

      %{"registerTemplate" => %{
          "id" => "...",
          "role" => %{"standaloneOutcome" => %{"sideNames" => [yes, no]}},
          "nameAndDescription" => [name, description],
          "keywordToHint" => [[keyword, "dateTime" | "date" | "string" | "hlPerp"], ...]}}

      %{"settleQuestion2" => %{
          "question" => 12,
          "outcomeSettlements" => [%{"outcome" => .., "settleFraction" => "..",
                                     "details" => "..",
                                     "nameAndDescription" => [n, d],
                                     "sideNames" => [yes, no]}, ...],
          "nameAndDescription" => [name, description]}}

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "validatorL1Votes",
    params: [],
    rate_limit_cost: 1,
    doc: "Retrieve validator L1 voting information",
    returns: "L1 voting information for validators"

  @type t :: %__MODULE__{
          votes: [Vote.t()]
        }

  @primary_key false
  embedded_schema do
    embeds_many :votes, Vote, primary_key: false do
      field(:validator, :string)
      # Variant name (object votes) or the raw string (string votes)
      field(:vote, :string)
      # Structured payload for object votes; nil for string votes
      field(:vote_data, :map)
      field(:time, :integer)
      field(:proposal_id, :integer)
    end
  end

  # ===================== Preprocessing =====================

  @doc false
  def preprocess(data) when is_list(data) do
    %{votes: data}
  end

  def preprocess(data), do: data

  # ===================== Changesets =====================

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(votes \\ %__MODULE__{}, attrs) do
    votes
    |> cast(attrs, [])
    |> cast_embed(:votes, with: &vote_changeset/2)
  end

  defp vote_changeset(vote, attrs) do
    attrs = normalize_attrs(attrs)

    vote
    |> cast(attrs, [:validator, :vote, :vote_data, :time, :proposal_id])
    |> validate_required([:validator, :vote, :time])
  end

  defp normalize_attrs(attrs) do
    {vote, vote_data} = normalize_vote(attrs["vote"] || attrs[:vote])

    %{
      validator: attrs["validator"] || attrs[:validator],
      vote: vote,
      vote_data: vote_data,
      time: attrs["time"] || attrs[:time],
      proposal_id: attrs["proposalId"] || attrs[:proposal_id]
    }
  end

  # Object votes are single-key maps naming the variant; keep both halves.
  defp normalize_vote(vote) when is_binary(vote), do: {vote, nil}

  defp normalize_vote(vote) when is_map(vote) and map_size(vote) == 1 do
    [{variant, _payload}] = Map.to_list(vote)
    {to_string(variant), vote}
  end

  defp normalize_vote(vote) when is_map(vote), do: {nil, vote}
  defp normalize_vote(_), do: {nil, nil}

  # ===================== Helpers =====================

  @doc """
  Return the structured payload of an object vote, or `nil` for a string vote.
  """
  @spec vote_payload(map()) :: map() | nil
  def vote_payload(%{vote: variant, vote_data: data}) when is_map(data) and is_binary(variant) do
    Map.get(data, variant)
  end

  def vote_payload(_), do: nil

  @doc "Votes of a given variant name (e.g. `\"settleQuestion2\"`)."
  @spec by_variant(t(), String.t()) :: [map()]
  def by_variant(%__MODULE__{votes: votes}, variant) do
    Enum.filter(votes, &(&1.vote == variant))
  end

  @spec by_validator(t(), String.t()) :: [map()]
  def by_validator(%__MODULE__{votes: votes}, validator) do
    val_lower = String.downcase(validator)
    Enum.filter(votes, &(String.downcase(&1.validator) == val_lower))
  end
end
