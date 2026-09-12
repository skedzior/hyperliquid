defmodule Hyperliquid.Api.Info.HistoricalOrders do
  @moduledoc """
  Historical orders for a user.

  Returns all historical orders including filled, canceled, and rejected orders.

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

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint#retrieve-a-users-historical-orders

  ## Usage

      {:ok, orders} = HistoricalOrders.request("0x1234...")
      filled = HistoricalOrders.filled(orders)
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "historicalOrders",
    params: [:user],
    rate_limit_cost: 2,
    doc: "Retrieve historical orders for a user",
    returns: "All historical orders including filled, canceled, and rejected orders",
    storage: [
      postgres: [
        enabled: true,
        table: "historical_orders",
        extract: :orders
      ],
      cache: [
        enabled: true,
        ttl: :timer.minutes(1),
        key_pattern: "historical_orders:{{user}}"
      ]
    ]

  @type t :: %__MODULE__{
          orders: [OrderRecord.t()]
        }

  @primary_key false
  embedded_schema do
    embeds_many :orders, OrderRecord, primary_key: false do
      @moduledoc "Historical order record."

      embeds_one :order, Order, primary_key: false do
        @moduledoc "Order details."

        field(:coin, :string)
        field(:side, :string)
        field(:limit_px, :string)
        field(:sz, :string)
        field(:oid, :integer)
        field(:timestamp, :integer)
        field(:trigger_condition, :string)
        field(:is_trigger, :boolean)
        field(:trigger_px, :string)
        field(:is_position_tpsl, :boolean)
        field(:reduce_only, :boolean)
        field(:order_type, :string)
        field(:orig_sz, :string)
        field(:tif, :string)
        field(:cloid, :string)
        field(:children, {:array, :map})
      end

      field(:status, :string)
      field(:status_timestamp, :integer)
    end
  end

  @statuses ~w(
    open
    filled
    canceled
    triggered
    rejected
    marginCanceled
    vaultWithdrawalCanceled
    openInterestCapCanceled
    selfTradeCanceled
    reduceOnlyCanceled
    siblingFilledCanceled
    delistedCanceled
    liquidatedCanceled
    outcomeSettledCanceled
    scheduledCancel
    internalCancel
    tickRejected
    minTradeNtlRejected
    perpMarginRejected
    reduceOnlyRejected
    badAloPxRejected
    iocCancelRejected
    badTriggerPxRejected
    marketOrderNoLiquidityRejected
    positionIncreaseAtOpenInterestCapRejected
    positionFlipAtOpenInterestCapRejected
    tooAggressiveAtOpenInterestCapRejected
    openInterestIncreaseRejected
    insufficientSpotBalanceRejected
    oracleRejected
    perpMaxPositionRejected
    tooManyOpenOrdersRejected
  )

  # ===================== Preprocessing =====================

  @doc false
  def preprocess(data) when is_list(data) do
    %{orders: data}
  end

  def preprocess(data), do: data

  # ===================== Storage Field Mapping =====================

  @doc """
  Flatten nested order record structure for postgres.
  Records have {order: {...}, status, status_timestamp} - merge order fields to top level.
  """
  def extract_postgres_fields(record) do
    order = safe_get(record, :order) || safe_get(record, "order") || %{}

    %{
      # Context field from request params (merged by extract_records)
      user: safe_get(record, :user) || safe_get(record, "user"),
      coin: safe_get(order, :coin) || safe_get(order, "coin"),
      side: safe_get(order, :side) || safe_get(order, "side"),
      limit_px: safe_get(order, :limit_px) || safe_get(order, "limitPx"),
      sz: safe_get(order, :sz) || safe_get(order, "sz"),
      oid: safe_get(order, :oid) || safe_get(order, "oid"),
      timestamp: safe_get(order, :timestamp) || safe_get(order, "timestamp"),
      orig_sz: safe_get(order, :orig_sz) || safe_get(order, "origSz"),
      cloid: safe_get(order, :cloid) || safe_get(order, "cloid"),
      order_type: safe_get(order, :order_type) || safe_get(order, "orderType"),
      tif: safe_get(order, :tif) || safe_get(order, "tif"),
      reduce_only: safe_get(order, :reduce_only) || safe_get(order, "reduceOnly"),
      status: safe_get(record, :status) || safe_get(record, "status"),
      status_timestamp: safe_get(record, :status_timestamp) || safe_get(record, "statusTimestamp")
    }
  end

  defp safe_get(%_{} = struct, key) when is_atom(key), do: Map.get(struct, key)
  defp safe_get(%_{}, _string_key), do: nil
  defp safe_get(map, key) when is_map(map), do: Map.get(map, key)
  defp safe_get(_, _), do: nil

  # ===================== Changesets =====================

  @doc """
  Get valid order statuses.

  ## Returns
    - List of valid status strings
  """
  @spec valid_statuses() :: [String.t()]
  def valid_statuses, do: @statuses

  @doc """
  Creates a changeset for historical orders data.

  ## Parameters
    - `historical`: The historical orders struct
    - `attrs`: Map with orders key

  ## Returns
    - `Ecto.Changeset.t()`
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(historical \\ %__MODULE__{}, attrs) do
    historical
    |> cast(attrs, [])
    |> cast_embed(:orders, with: &order_record_changeset/2)
  end

  defp order_record_changeset(record, attrs) do
    record
    |> cast(attrs, [:status, :status_timestamp])
    |> cast_embed(:order, with: &order_changeset/2)
    |> validate_required([:status])
  end

  defp order_changeset(order, attrs) do
    order
    |> cast(attrs, [
      :coin,
      :side,
      :limit_px,
      :sz,
      :oid,
      :timestamp,
      :trigger_condition,
      :is_trigger,
      :trigger_px,
      :is_position_tpsl,
      :reduce_only,
      :order_type,
      :orig_sz,
      :tif,
      :cloid,
      :children
    ])
    |> validate_required([:coin, :side, :oid])
  end

  # ===================== Helpers =====================

  @doc """
  Filter orders by status.

  ## Parameters
    - `historical`: The historical orders struct
    - `status`: Status to filter by

  ## Returns
    - List of order records matching status
  """
  @spec by_status(t(), String.t()) :: [map()]
  def by_status(%__MODULE__{orders: orders}, status) when is_binary(status) do
    Enum.filter(orders, &(&1.status == status))
  end

  @doc """
  Filter orders by coin.

  ## Parameters
    - `historical`: The historical orders struct
    - `coin`: Coin symbol

  ## Returns
    - List of order records for the coin
  """
  @spec by_coin(t(), String.t()) :: [map()]
  def by_coin(%__MODULE__{orders: orders}, coin) when is_binary(coin) do
    Enum.filter(orders, &(&1.order.coin == coin))
  end

  @doc """
  Get filled orders only.

  ## Parameters
    - `historical`: The historical orders struct

  ## Returns
    - List of filled order records
  """
  @spec filled(t()) :: [map()]
  def filled(%__MODULE__{} = historical) do
    by_status(historical, "filled")
  end

  @doc """
  Get canceled orders only.

  ## Parameters
    - `historical`: The historical orders struct

  ## Returns
    - List of canceled order records
  """
  @spec canceled(t()) :: [map()]
  def canceled(%__MODULE__{} = historical) do
    by_status(historical, "canceled")
  end

  @doc """
  Find order by OID.

  ## Parameters
    - `historical`: The historical orders struct
    - `oid`: Order ID

  ## Returns
    - `{:ok, OrderRecord.t()}` if found
    - `{:error, :not_found}` if not found
  """
  @spec find_by_oid(t(), integer()) :: {:ok, map()} | {:error, :not_found}
  def find_by_oid(%__MODULE__{orders: orders}, oid) when is_integer(oid) do
    case Enum.find(orders, &(&1.order.oid == oid)) do
      nil -> {:error, :not_found}
      order -> {:ok, order}
    end
  end
end
