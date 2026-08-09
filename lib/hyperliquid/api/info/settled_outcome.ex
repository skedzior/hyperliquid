defmodule Hyperliquid.Api.Info.SettledOutcome do
  @moduledoc """
  Settlement information for a HIP-4 prediction market outcome.

  Returns `nil` when the outcome exists but has not settled yet.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint/spot

  ## Usage

      {:ok, settled} = SettledOutcome.request(7)
      SettledOutcome.settled?(settled)
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "settledOutcome",
    params: [:outcome],
    rate_limit_cost: 2,
    doc: "Retrieve settlement information for an outcome",
    returns: "Settlement details, or null when the outcome has not settled",
    storage: [
      cache: [
        enabled: true,
        ttl: :timer.minutes(1),
        key_pattern: "settled_outcome:{{outcome}}"
      ]
    ]

  @type t :: %__MODULE__{
          spec: map() | nil,
          settle_fraction: String.t() | nil,
          details: String.t() | nil,
          question: map() | nil
        }

  @primary_key false
  embedded_schema do
    field(:spec, :map)
    field(:settle_fraction, :string)
    field(:details, :string)
    field(:question, :map)
  end

  # ===================== Preprocessing =====================

  @doc false
  # An unsettled outcome comes back as a bare null.
  def preprocess(nil), do: %{}
  def preprocess(data), do: data

  # ===================== Changesets =====================

  @doc """
  Creates a changeset for settled outcome data.

  ## Parameters
    - `outcome`: The settled outcome struct
    - `attrs`: Map of attributes

  ## Returns
    - `Ecto.Changeset.t()`
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(outcome \\ %__MODULE__{}, attrs) do
    cast(outcome, attrs, [:spec, :settle_fraction, :details, :question])
  end

  # ===================== Helpers =====================

  @doc """
  Whether the outcome has settled.

  ## Parameters
    - `outcome`: The settled outcome struct

  ## Returns
    - `boolean()`
  """
  @spec settled?(t() | nil) :: boolean()
  def settled?(nil), do: false
  def settled?(%__MODULE__{spec: nil}), do: false
  def settled?(%__MODULE__{}), do: true

  @doc """
  Settlement fraction as a float.

  ## Parameters
    - `outcome`: The settled outcome struct

  ## Returns
    - `{:ok, float()}` when settled
    - `{:error, :not_settled}` otherwise
  """
  @spec settle_fraction(t()) :: {:ok, float()} | {:error, :not_settled}
  def settle_fraction(%__MODULE__{settle_fraction: nil}), do: {:error, :not_settled}

  def settle_fraction(%__MODULE__{settle_fraction: fraction}) when is_binary(fraction) do
    case Float.parse(fraction) do
      {value, _} -> {:ok, value}
      :error -> {:error, :not_settled}
    end
  end

  @doc """
  Whether the outcome resolved fully to the YES side.

  ## Parameters
    - `outcome`: The settled outcome struct

  ## Returns
    - `boolean()`
  """
  @spec resolved_yes?(t()) :: boolean()
  def resolved_yes?(%__MODULE__{} = outcome) do
    case settle_fraction(outcome) do
      {:ok, fraction} -> fraction == 1.0
      _ -> false
    end
  end
end
