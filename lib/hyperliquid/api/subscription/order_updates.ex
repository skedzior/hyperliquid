defmodule Hyperliquid.Api.Subscription.OrderUpdates do
  @moduledoc """
  WebSocket subscription for order status updates.

  ## `status` values

  See `Hyperliquid.Api.Info.HistoricalOrders.valid_statuses/0` for the full
  `OrderProcessingStatus` list. Three values were added upstream in v0.33.3:
  `"outcomeSettledCanceled"`, `"internalCancel"` and `"tooManyOpenOrdersRejected"`.
  The field is an unconstrained string, so no cast breaks; audit any downstream
  pattern match.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/subscriptions
  """

  use Hyperliquid.Api.SubscriptionEndpoint,
    request_type: "orderUpdates",
    params: [:user],
    connection_type: :user_grouped,
    doc: "Order updates - shares connection per user"

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:order, :map)
    field(:status, :string)
    field(:status_timestamp, :integer)
  end

  @spec build_request(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def build_request(params) do
    types = %{user: :string}

    changeset =
      {%{}, types}
      |> cast(params, Map.keys(types))
      |> validate_required([:user])
      |> validate_format(:user, ~r/^0x[0-9a-fA-F]{40}$/)

    if changeset.valid? do
      {:ok, %{type: "orderUpdates", user: get_change(changeset, :user)}}
    else
      {:error, changeset}
    end
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event \\ %__MODULE__{}, attrs) do
    event
    |> cast(attrs, [:order, :status, :status_timestamp])
  end
end
