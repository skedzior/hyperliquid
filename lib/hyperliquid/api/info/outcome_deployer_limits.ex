defmodule Hyperliquid.Api.Info.OutcomeDeployerLimits do
  @moduledoc """
  Remaining HIP-4 deployment quota for an outcome deployer venue.

  Request: `%{type: "outcomeDeployerLimits", venue: "abc"}` where `venue` is the
  2-4 lowercase-ASCII venue name registered via `activateOutcomeDeployer`.

  Returns the deployer's remaining daily-deployment quota and remaining
  active-outcome quota (testnet caps at the time of writing: 50 outcomes/day,
  10 active per deployer).

  > #### Response shape is not pinned {: .warning}
  > This endpoint is documented on the official info/spot page but has **no
  > `@nktkas/hyperliquid` counterpart**, so the response is kept as an untyped
  > passthrough under `:data` rather than guessing field names.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint/spot

  ## Usage

      {:ok, limits} = OutcomeDeployerLimits.request("abc")
      limits.data
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "outcomeDeployerLimits",
    params: [:venue],
    rate_limit_cost: 20,
    doc: "Retrieve remaining HIP-4 deployment quota for a venue",
    returns: "Remaining daily-deployment and active-outcome quota",
    raw_response: true

  @venue_format ~r/^[a-z]{2,4}$/

  @type t :: %__MODULE__{
          data: map()
        }

  @primary_key false
  embedded_schema do
    field(:data, :map)
  end

  @doc """
  Returns true when `venue` matches the documented 2-4 lowercase-letter format.
  """
  @spec valid_venue?(term()) :: boolean()
  def valid_venue?(venue) when is_binary(venue), do: Regex.match?(@venue_format, venue)
  def valid_venue?(_), do: false

  # ===================== Preprocessing =====================

  @doc false
  def preprocess(data) when is_map(data), do: %{data: data}
  def preprocess(nil), do: %{data: %{}}
  def preprocess(data), do: %{data: %{"value" => data}}

  # ===================== Changesets =====================

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(limits \\ %__MODULE__{}, attrs) do
    limits
    |> cast(attrs, [:data])
  end
end
