defmodule Hyperliquid.Api.Info.UserBorrowLendInterest do
  @moduledoc """
  User's accrued borrow/lend interest across all positions.

  Returns interest accrued for each token in which the user has an active
  borrow or lend position in the borrow/lend protocol.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint

  ## Usage

      {:ok, interest} = UserBorrowLendInterest.request("0x...")
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "userBorrowLendInterest",
    params: [:user],
    rate_limit_cost: 20,
    doc: "Retrieve user's accrued interest across all borrow/lend positions",
    returns: "Accrued interest per token for the user's borrow/lend positions",
    raw_response: true

  @type t :: %__MODULE__{
          data: map() | list()
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
end
