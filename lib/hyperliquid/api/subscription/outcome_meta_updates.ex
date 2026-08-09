defmodule Hyperliquid.Api.Subscription.OutcomeMetaUpdates do
  @moduledoc """
  WebSocket subscription for HIP-4 prediction market metadata changes.

  Each event carries a list of updates, where every update is a single-key map
  naming what changed:

  - `outcomeCreated` - a new outcome, with its side specs and quote token
  - `outcomeSettled` - an outcome identifier that has settled
  - `questionUpdated` - a question's named outcomes or text changed
  - `questionSettled` - a question identifier that has settled

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/subscriptions

  ## Usage

      {:ok, request} = OutcomeMetaUpdates.build_request()
      # => {:ok, %{type: "outcomeMetaUpdates"}}
  """

  use Hyperliquid.Api.SubscriptionEndpoint,
    request_type: "outcomeMetaUpdates",
    connection_type: :shared,
    doc: "HIP-4 outcome and question metadata updates - can share connection"

  @type t :: %__MODULE__{updates: [map()]}

  @primary_key false
  embedded_schema do
    field(:updates, {:array, :map})
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event \\ %__MODULE__{}, attrs) do
    cast(event, attrs, [:updates])
  end

  # ===================== Helpers =====================

  @doc """
  Split an event's updates by kind.

  ## Parameters
    - `event`: The subscription event

  ## Returns
    - Map keyed by update kind, each holding the payloads of that kind

  ## Examples

      OutcomeMetaUpdates.group_updates(event)
      # => %{"outcomeCreated" => [...], "questionSettled" => [...]}
  """
  @spec group_updates(t() | map()) :: %{optional(String.t()) => [map()]}
  def group_updates(%__MODULE__{updates: updates}), do: do_group(updates)
  def group_updates(%{updates: updates}), do: do_group(updates)
  def group_updates(_), do: %{}

  defp do_group(updates) when is_list(updates) do
    updates
    |> Enum.flat_map(&Map.to_list/1)
    |> Enum.group_by(fn {kind, _payload} -> to_string(kind) end, fn {_kind, payload} ->
      payload
    end)
  end

  defp do_group(_), do: %{}

  @doc """
  Outcome identifiers that settled in this event.

  ## Parameters
    - `event`: The subscription event

  ## Returns
    - List of settled outcome identifiers
  """
  @spec settled_outcomes(t() | map()) :: [non_neg_integer()]
  def settled_outcomes(event) do
    event
    |> group_updates()
    |> Map.get("outcomeSettled", [])
    |> Enum.map(fn payload -> payload["outcome"] || payload[:outcome] end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Question identifiers that settled in this event.

  ## Parameters
    - `event`: The subscription event

  ## Returns
    - List of settled question identifiers
  """
  @spec settled_questions(t() | map()) :: [non_neg_integer()]
  def settled_questions(event) do
    event
    |> group_updates()
    |> Map.get("questionSettled", [])
    |> Enum.map(fn payload -> payload["question"] || payload[:question] end)
    |> Enum.reject(&is_nil/1)
  end
end
