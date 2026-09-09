defmodule Hyperliquid.Api.Info.OrderStatus do
  @moduledoc """
  Status of a specific order.

  Returns detailed status information for an order by OID or CLOID.

  ## `status` values

  See `Hyperliquid.Api.Info.HistoricalOrders.valid_statuses/0` for the full
  `OrderProcessingStatus` list. Three values were added upstream in v0.33.3:
  `"outcomeSettledCanceled"`, `"internalCancel"` and `"tooManyOpenOrdersRejected"`.
  The field is an unconstrained string, so no cast breaks; audit any downstream
  pattern match.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint#query-order-status-by-oid-or-cloid
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "orderStatus",
    params: [:user, :oid],
    rate_limit_cost: 1,
    doc: "Query order status by OID or CLOID",
    returns: "Detailed order status information",
    storage: [
      postgres: [
        enabled: true,
        table: "order_status"
      ],
      cache: [
        enabled: true,
        ttl: :timer.seconds(5),
        key_pattern: "order:{{user}}:{{oid}}"
      ]
    ]

  alias Hyperliquid.Transport.Http

  @type t :: %__MODULE__{
          status: String.t(),
          order: Order.t() | nil
        }

  @primary_key false
  embedded_schema do
    field(:status, :string)

    embeds_one :order, Order, primary_key: false do
      @moduledoc "Order details."

      field(:coin, :string)
      field(:side, :string)
      field(:limit_px, :string)
      field(:sz, :string)
      field(:oid, :integer)
      field(:timestamp, :integer)
      field(:orig_sz, :string)
      field(:cloid, :string)
      # Inner status from API (open, filled, etc)
      field(:order_status, :string)
    end
  end

  # ===================== Preprocessing =====================

  @doc false
  def preprocess(%{"status" => status, "order" => inner}) when is_map(inner) do
    # API returns nested: {status: "order", order: {order: {...}, status: "open", ...}}
    order_data = inner["order"] || inner
    order_status = inner["status"]

    # Flatten and normalize
    %{
      "status" => status,
      "order" => Map.merge(order_data, %{"order_status" => order_status})
    }
  end

  def preprocess(data), do: data

  # ===================== Storage Field Mapping =====================

  @doc """
  Extract order fields for postgres storage.
  Maps embedded order to flat record with normalized field names.
  """
  def extract_postgres_fields(data) do
    # Handle both struct and map access (structs don't implement Access)
    order = safe_get(data, :order) || safe_get(data, "order") || %{}

    # Prefer inner order_status (open, filled, etc) over outer status ("order")
    status =
      safe_get(order, :order_status) || safe_get(order, "order_status") ||
        safe_get(data, :status) || safe_get(data, "status")

    %{
      # Context field from request params (merged by extract_records)
      user: safe_get(data, :user) || safe_get(data, "user"),
      status: status,
      coin: safe_get(order, :coin) || safe_get(order, "coin"),
      side: safe_get(order, :side) || safe_get(order, "side"),
      limit_px:
        safe_get(order, :limit_px) || safe_get(order, "limitPx") || safe_get(order, "limit_px"),
      sz: safe_get(order, :sz) || safe_get(order, "sz"),
      oid: safe_get(order, :oid) || safe_get(order, "oid"),
      timestamp: safe_get(order, :timestamp) || safe_get(order, "timestamp"),
      orig_sz:
        safe_get(order, :orig_sz) || safe_get(order, "origSz") || safe_get(order, "orig_sz"),
      cloid: safe_get(order, :cloid) || safe_get(order, "cloid")
    }
  end

  # Safe field access that works for both structs and maps
  defp safe_get(%_{} = struct, key) when is_atom(key), do: Map.get(struct, key)
  defp safe_get(%_{}, _string_key), do: nil
  defp safe_get(map, key) when is_map(map), do: Map.get(map, key)
  defp safe_get(_, _), do: nil

  # ===================== Custom Request Methods =====================

  @doc """
  Build the request payload for orderStatus by CLOID.

  ## Parameters
    - `user`: User address (0x...)
    - `cloid`: Client order ID
  """
  @spec build_request_by_cloid(String.t(), String.t()) :: map()
  def build_request_by_cloid(user, cloid) do
    %{type: "orderStatus", user: user, cloid: cloid}
  end

  @doc """
  Fetches order status by CLOID from the API.

  ## Parameters
    - `user`: User address (0x...)
    - `cloid`: Client order ID

  ## Returns
    - `{:ok, %OrderStatus{}}` - Parsed and validated order status
    - `{:error, term()}` - Error from HTTP or validation
  """
  @spec request_by_cloid(String.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def request_by_cloid(user, cloid) do
    with {:ok, data} <- Http.info_request(build_request_by_cloid(user, cloid)),
         {:ok, result} <- parse_response(data) do
      {:ok, result}
    end
  end

  # ===================== Changesets =====================

  @doc """
  Creates a changeset for order status data.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(order_status \\ %__MODULE__{}, attrs) do
    order_status
    |> cast(attrs, [:status])
    |> cast_embed(:order, with: &order_changeset/2)
    |> validate_required([:status])
  end

  defp order_changeset(order, attrs) do
    # Normalize API field names (limitPx -> limit_px, origSz -> orig_sz)
    normalized = normalize_order_attrs(attrs)

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
      :order_status
    ])
  end

  defp normalize_order_attrs(attrs) when is_map(attrs) do
    %{
      coin: attrs["coin"] || attrs[:coin],
      side: attrs["side"] || attrs[:side],
      limit_px: attrs["limitPx"] || attrs["limit_px"] || attrs[:limit_px],
      sz: attrs["sz"] || attrs[:sz],
      oid: attrs["oid"] || attrs[:oid],
      timestamp: attrs["timestamp"] || attrs[:timestamp],
      orig_sz: attrs["origSz"] || attrs["orig_sz"] || attrs[:orig_sz],
      cloid: attrs["cloid"] || attrs[:cloid],
      order_status: attrs["order_status"] || attrs[:order_status]
    }
  end

  # ===================== Helpers =====================

  @doc """
  Check if order is filled.
  """
  @spec filled?(t()) :: boolean()
  def filled?(%__MODULE__{status: status}), do: status == "filled"

  @doc """
  Check if order is open.
  """
  @spec open?(t()) :: boolean()
  def open?(%__MODULE__{status: status}), do: status == "open"

  @doc """
  Check if order is canceled.
  """
  @spec canceled?(t()) :: boolean()
  def canceled?(%__MODULE__{status: status}), do: status == "canceled"
end
