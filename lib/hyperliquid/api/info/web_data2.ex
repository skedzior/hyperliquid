defmodule Hyperliquid.Api.Info.WebData2 do
  @moduledoc """
  One-shot REST snapshot of comprehensive user and market data.

  Returns a full snapshot equivalent to the `webData2` WebSocket subscription,
  including clearinghouse state, open orders, vault info, market metadata,
  TWAP states, and spot state for the given user.

  The subscription-based version lives at
  `Hyperliquid.Api.Subscription.WebData2`. This module is the REST POST
  equivalent — useful for an initial load without subscribing to a stream.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint

  ## Usage

      {:ok, snapshot} = WebData2.request("0x...")
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "webData2",
    params: [:user],
    rate_limit_cost: 20,
    doc: "Retrieve one-shot snapshot of comprehensive user and market data",
    returns: "Full webData2 snapshot including clearinghouse, orders, vaults, and market data",
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
  def preprocess(data) when is_map(data), do: %{data: data}
  def preprocess(data), do: %{data: data}

  # ===================== Changesets =====================

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(state \\ %__MODULE__{}, attrs) do
    state
    |> cast(attrs, [:data])
  end
end
