defmodule Hyperliquid.Api.Subscription.UserHistoricalOrders do
  @moduledoc """
  WebSocket subscription for historical order updates.

  ## `status` values

  See `Hyperliquid.Api.Info.HistoricalOrders.valid_statuses/0` for the full
  `OrderProcessingStatus` list. Three values were added upstream in v0.33.3:
  `"outcomeSettledCanceled"`, `"internalCancel"` and `"tooManyOpenOrdersRejected"`.
  The field is an unconstrained string, so no cast breaks; audit any downstream
  pattern match.

  ## `order_type` values

  `"Market"`, `"Limit"`, `"Stop Market"`, `"Stop Limit"`, `"Take Profit Market"`,
  `"Take Profit Limit"`, and - added upstream in v0.33.3 - `"Twap Slice"`,
  `"Vault Close"`, `"Spot Dust Conversion"`. The field is an unconstrained string,
  so no cast breaks; audit any downstream pattern match.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/subscriptions
  """

  use Hyperliquid.Api.SubscriptionEndpoint,
    request_type: "userHistoricalOrders",
    params: [:user],
    connection_type: :user_grouped,
    doc: "User historical orders - shares connection per user",
    storage: [
      postgres: [
        enabled: true,
        table: "historical_orders",
        extract: "orderHistory"
      ],
      cache: [
        enabled: true,
        ttl: :timer.minutes(5),
        key_pattern: "historical_orders:ws:{{user}}"
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
      field(:cloid, :string)
      field(:order_type, :string)
      field(:tif, :string)
      field(:reduce_only, :boolean)
      field(:status, :string)
      field(:status_timestamp, :integer)
    end
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
      {:ok, %{type: "userHistoricalOrders", user: get_change(changeset, :user)}}
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
    # Handle nested structure: %{"order" => %{...}, "status" => "...", ...}
    # Extract nested order object and merge with top-level fields
    order_data = fetch_field(attrs, ["order"], attrs)

    normalized = %{
      coin: fetch_field(order_data, ["coin"], nil),
      side: fetch_field(order_data, ["side"], nil),
      limit_px: fetch_field(order_data, ["limitPx", "limit_px"], nil),
      sz: fetch_field(order_data, ["sz"], nil),
      oid: fetch_field(order_data, ["oid"], nil),
      timestamp: fetch_field(order_data, ["timestamp"], nil),
      orig_sz: fetch_field(order_data, ["origSz", "orig_sz"], nil),
      cloid: fetch_field(order_data, ["cloid"], nil),
      order_type: fetch_field(order_data, ["orderType", "order_type"], nil),
      tif: fetch_field(order_data, ["tif"], nil),
      reduce_only: fetch_field(order_data, ["reduceOnly", "reduce_only"], nil),
      status: fetch_field(attrs, ["status"], nil),
      status_timestamp: fetch_field(attrs, ["statusTimestamp", "status_timestamp"], nil)
    }

    order
    |> cast(normalized, [
      :coin,
      :side,
      :limit_px,
      :sz,
      :oid,
      :timestamp,
      :orig_sz,
      :cloid,
      :order_type,
      :tif,
      :reduce_only,
      :status,
      :status_timestamp
    ])
  end

  # ===================== Storage Field Mapping =====================

  # Override DSL-generated function to normalize field names
  def extract_postgres_fields(data) do
    normalize_order_attrs(data)
  end

  defp normalize_order_attrs(attrs) when is_map(attrs) do
    # WebSocket structure: %{"order" => %{coin, side, ...}, "status" => "...", "statusTimestamp" => ...}
    # Extract the nested order details
    order = fetch_field(attrs, ["order"], %{})

    # Merge top-level fields with nested order fields
    %{
      # Context field from request params (merged by extract_records)
      user: fetch_field(attrs, ["user"], nil),
      # Top-level status fields
      status: fetch_field(attrs, ["status"], nil),
      status_timestamp: fetch_field(attrs, ["statusTimestamp", "status_timestamp"], nil),
      # Order details from nested "order" object
      coin: fetch_field(order, ["coin"], nil),
      side: fetch_field(order, ["side"], nil),
      limit_px: fetch_field(order, ["limitPx", "limit_px"], nil),
      sz: fetch_field(order, ["sz"], nil),
      oid: fetch_field(order, ["oid"], nil),
      timestamp: fetch_field(order, ["timestamp"], nil),
      orig_sz: fetch_field(order, ["origSz", "orig_sz"], nil),
      cloid: fetch_field(order, ["cloid"], nil),
      order_type: fetch_field(order, ["orderType", "order_type"], nil),
      tif: fetch_field(order, ["tif"], nil),
      reduce_only: fetch_field(order, ["reduceOnly", "reduce_only"], nil)
    }
  end

  # Get field value, trying multiple key variants (string and atom)
  defp fetch_field(attrs, [key | rest], default) when is_binary(key) do
    case Map.get(attrs, key) do
      nil ->
        # Try atom version if it exists
        try do
          atom_key = String.to_existing_atom(key)
          Map.get(attrs, atom_key) || fetch_field(attrs, rest, default)
        rescue
          ArgumentError -> fetch_field(attrs, rest, default)
        end

      value ->
        value
    end
  end

  defp fetch_field(_attrs, [], default), do: default
end
