defmodule Hyperliquid.Api.Info.BorrowLendUserState do
  @moduledoc """
  User's borrow/lend positions and account health.

  Returns the user's current borrow and lending positions, including basis values
  and account health metrics.

  ## Response shape (untyped passthrough under `:data`)

  Two fields widened upstream in `@nktkas/hyperliquid` (commit `5aef828`):

  - `health` - was always `"healthy"`; now one of `"healthy"`, `"atRisk"`,
    `"marketLiquidatable"`, `"backstopLiquidatable"`
  - `healthFactor` - was always `null`; now `string | null`

  Because `:data` is an untyped map neither change breaks casting, but callers
  that assumed `health == "healthy"` must be audited. Use `health/1` and
  `at_risk?/1`.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint

  ## Usage

      {:ok, state} = BorrowLendUserState.request("0x...")
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "borrowLendUserState",
    params: [:user],
    rate_limit_cost: 20,
    doc: "Retrieve user's borrow/lend positions and account health",
    returns: "User's borrow/lend state including positions and health metrics",
    raw_response: true

  @type t :: %__MODULE__{
          data: map()
        }

  @primary_key false
  embedded_schema do
    field(:data, :map)
  end

  # ===================== Preprocessing =====================

  @doc false
  def preprocess(data) when is_list(data), do: %{data: %{positions: data}}
  def preprocess(data) when is_map(data), do: %{data: data}
  def preprocess(data), do: %{data: data}

  # ===================== Changesets =====================

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(state \\ %__MODULE__{}, attrs) do
    state
    |> cast(attrs, [:data])
  end

  # ===================== Helpers =====================

  @health_states ~w(healthy atRisk marketLiquidatable backstopLiquidatable)

  @doc "Known `health` values."
  @spec health_states() :: [String.t()]
  def health_states, do: @health_states

  @doc "Account health string, or `nil` when absent."
  @spec health(t()) :: String.t() | nil
  def health(%__MODULE__{data: data}) when is_map(data), do: data["health"] || data[:health]
  def health(_), do: nil

  @doc "Health factor string (`nil` when the server reports none)."
  @spec health_factor(t()) :: String.t() | nil
  def health_factor(%__MODULE__{data: data}) when is_map(data),
    do: data["health_factor"] || data[:health_factor] || data["healthFactor"]

  def health_factor(_), do: nil

  @doc "True when health is anything other than `\"healthy\"`."
  @spec at_risk?(t()) :: boolean()
  def at_risk?(state) do
    case health(state) do
      nil -> false
      "healthy" -> false
      _ -> true
    end
  end
end
