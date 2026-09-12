defmodule Hyperliquid.Api.Info.TwapHistory do
  @moduledoc """
  TWAP order history for a user.

  Returns historical TWAP (Time-Weighted Average Price) orders.

  ## Trigger / stop price (nktkas `18bbcda`, `bb50731`)

  Each record's `state` now carries:

  - `stop_px` - price at which the TWAP is terminated, or `nil`
  - `trigger` - `%{"px" => "...", "above" => bool}` activation condition, or `nil`
    (`above: true` triggers when the mark price rises above `px`)

  ## Status values

  `status.status` gained `"waitingForTrigger"` and `"stopped"` on top of the
  original `"finished"`, `"activated"`, `"terminated"` and `"error"`. The field is
  a plain string so nothing breaks, but note that `active/1` matches only
  `"activated"` - a TWAP parked on a trigger reports `"waitingForTrigger"`. Use
  `pending?/1` when you mean "not finished yet".

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "twapHistory",
    params: [:user],
    rate_limit_cost: 1,
    doc: "Retrieve user's TWAP order history",
    returns: "Historical TWAP orders"

  @type t :: %__MODULE__{
          records: [Record.t()]
        }

  @primary_key false
  embedded_schema do
    embeds_many :records, Record, primary_key: false do
      @moduledoc "TWAP history record."

      field(:time, :integer)
      field(:twap_id, :integer)

      embeds_one :state, State, primary_key: false do
        @moduledoc "TWAP order state."

        field(:coin, :string)
        field(:executed_ntl, :string)
        field(:executed_sz, :string)
        field(:minutes, :integer)
        field(:randomize, :boolean)
        field(:reduce_only, :boolean)
        field(:side, :string)
        # Price at which the order is terminated; nil when unset
        field(:stop_px, :string)
        field(:sz, :string)
        field(:timestamp, :integer)
        # %{"px" => "...", "above" => bool} activation condition; nil when unset
        field(:trigger, :map)
        field(:user, :string)
      end

      embeds_one :status, Status, primary_key: false do
        @moduledoc "TWAP order status."

        field(:status, :string)
        field(:description, :string)
      end
    end
  end

  # ===================== Preprocessing =====================

  @doc false
  def preprocess(data) when is_list(data) do
    %{records: data}
  end

  def preprocess(data), do: data

  # ===================== Changesets =====================

  @doc """
  Creates a changeset for TWAP history data.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(history \\ %__MODULE__{}, attrs) do
    history
    |> cast(attrs, [])
    |> cast_embed(:records, with: &record_changeset/2)
  end

  defp record_changeset(record, attrs) do
    record
    |> cast(attrs, [:time, :twap_id])
    |> cast_embed(:state, with: &state_changeset/2)
    |> cast_embed(:status, with: &status_changeset/2)
    |> validate_required([:time])
  end

  defp state_changeset(state, attrs) do
    state
    |> cast(attrs, [
      :coin,
      :executed_ntl,
      :executed_sz,
      :minutes,
      :randomize,
      :reduce_only,
      :side,
      :stop_px,
      :sz,
      :timestamp,
      :trigger,
      :user
    ])
    |> validate_required([:coin, :side, :sz, :minutes, :timestamp])
  end

  defp status_changeset(status, attrs) do
    status
    |> cast(attrs, [:status, :description])
    |> validate_required([:status])
  end

  # ===================== Statuses =====================

  @statuses ~w(finished activated terminated waitingForTrigger stopped error)

  @doc """
  Known `status.status` values.

  `"waitingForTrigger"` and `"stopped"` were added upstream in v0.33.3.
  """
  @spec valid_statuses() :: [String.t()]
  def valid_statuses, do: @statuses

  # ===================== Helpers =====================

  @doc """
  Get records by coin.
  """
  @spec by_coin(t(), String.t()) :: [map()]
  def by_coin(%__MODULE__{records: records}, coin) do
    Enum.filter(records, &(&1.state && &1.state.coin == coin))
  end

  @doc """
  Get records whose status is exactly `"activated"`.

  Note this excludes TWAPs parked on a trigger - see `waiting_for_trigger/1` and
  `pending/1`.
  """
  @spec active(t()) :: [map()]
  def active(%__MODULE__{records: records}) do
    Enum.filter(records, &(&1.status && &1.status.status == "activated"))
  end

  @doc "Records awaiting their trigger price (`\"waitingForTrigger\"`)."
  @spec waiting_for_trigger(t()) :: [map()]
  def waiting_for_trigger(%__MODULE__{records: records}) do
    Enum.filter(records, &(&1.status && &1.status.status == "waitingForTrigger"))
  end

  @doc """
  Records that are not in a terminal state - i.e. `"activated"` or
  `"waitingForTrigger"`.
  """
  @spec pending(t()) :: [map()]
  def pending(%__MODULE__{records: records}) do
    Enum.filter(records, &(&1.status && &1.status.status in ["activated", "waitingForTrigger"]))
  end
end
