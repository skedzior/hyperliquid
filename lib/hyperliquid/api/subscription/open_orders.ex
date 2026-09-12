defmodule Hyperliquid.Api.Subscription.OpenOrders do
  @moduledoc """
  WebSocket subscription for open orders.

  `dex` is optional and defaults to `""` (the main dex), matching
  `@nktkas/hyperliquid` - the response always echoes the dex back.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/subscriptions
  """

  use Hyperliquid.Api.SubscriptionEndpoint,
    request_type: "openOrders",
    params: [:user],
    optional_params: [:dex],
    connection_type: :user_grouped,
    doc: "Open orders - shares connection per user",
    storage: [
      postgres: [
        enabled: true,
        table: "orders",
        extract: :orders
      ],
      cache: [
        enabled: true,
        ttl: :timer.seconds(10),
        key_pattern: "open_orders:{{user}}"
      ]
    ]

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    embeds_many :orders, Order, primary_key: false do
      field(:coin, :string)
      field(:side, :string)
      field(:limit_px, :string)
      field(:sz, :string)
      field(:oid, :integer)
      field(:timestamp, :integer)
      field(:orig_sz, :string)
    end
  end

  @spec build_request(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def build_request(params) do
    types = %{user: :string, dex: :string}

    changeset =
      {%{}, types}
      |> cast(params, Map.keys(types))
      |> validate_required([:user])
      |> validate_format(:user, ~r/^0x[0-9a-fA-F]{40}$/)

    if changeset.valid? do
      {:ok,
       %{
         type: "openOrders",
         user: get_change(changeset, :user),
         dex: get_change(changeset, :dex) || ""
       }}
    else
      {:error, changeset}
    end
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event \\ %__MODULE__{}, attrs) do
    event
    |> cast(attrs, [])
    |> cast_embed(:orders, with: &order_changeset/2)
  end

  defp order_changeset(order, attrs) do
    order
    |> cast(attrs, [:coin, :side, :limit_px, :sz, :oid, :timestamp, :orig_sz])
  end
end
