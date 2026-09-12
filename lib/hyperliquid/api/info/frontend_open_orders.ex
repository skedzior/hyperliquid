defmodule Hyperliquid.Api.Info.FrontendOpenOrders do
  @moduledoc """
  Open orders with frontend display information.

  Similar to openOrders but includes additional display fields used by the frontend.

  ## `order_type` values

  `"Market"`, `"Limit"`, `"Stop Market"`, `"Stop Limit"`, `"Take Profit Market"`,
  `"Take Profit Limit"`, and - added upstream in v0.33.3 - `"Twap Slice"`,
  `"Vault Close"`, `"Spot Dust Conversion"`. The field is an unconstrained string,
  so no cast breaks; audit any downstream pattern match.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint#retrieve-a-users-open-orders-with-additional-frontend-info

  ## Usage

      {:ok, orders} = FrontendOpenOrders.request("0x1234...")
      {:ok, orders} = FrontendOpenOrders.request("0x1234...", dex: "some_dex")
      buys = FrontendOpenOrders.buys(orders)
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "frontendOpenOrders",
    params: [:user],
    optional_params: [:dex],
    rate_limit_cost: 2,
    doc: "Retrieve open orders with frontend display information",
    returns: "List of open orders with additional display fields"

  @type t :: %__MODULE__{
          orders: [Order.t()]
        }

  @primary_key false
  embedded_schema do
    embeds_many :orders, Order, primary_key: false do
      @moduledoc "Open order with frontend info."

      field(:coin, :string)
      field(:side, :string)
      field(:limit_px, :string)
      field(:sz, :string)
      field(:oid, :integer)
      field(:timestamp, :integer)
      field(:orig_sz, :string)
      field(:trigger_condition, :string)
      field(:is_trigger, :boolean)
      field(:trigger_px, :string)
      field(:is_position_tpsl, :boolean)
      field(:reduce_only, :boolean)
      field(:order_type, :string)
      field(:cloid, :string)
    end
  end

  # ===================== Preprocessing =====================

  @doc false
  def preprocess(data) when is_list(data) do
    %{orders: data}
  end

  def preprocess(data), do: data

  # ===================== Changesets =====================

  @doc """
  Creates a changeset for frontend open orders data.

  ## Parameters
    - `orders`: The frontend open orders struct
    - `attrs`: Map with orders key

  ## Returns
    - `Ecto.Changeset.t()`
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(orders \\ %__MODULE__{}, attrs) do
    orders
    |> cast(attrs, [])
    |> cast_embed(:orders, with: &order_changeset/2)
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
      :orig_sz,
      :trigger_condition,
      :is_trigger,
      :trigger_px,
      :is_position_tpsl,
      :reduce_only,
      :order_type,
      :cloid
    ])
    |> validate_required([:coin, :side, :oid])
  end

  # ===================== Helpers =====================

  @doc """
  Get buy orders.

  ## Parameters
    - `orders`: The frontend open orders struct

  ## Returns
    - List of buy orders
  """
  @spec buys(t()) :: [map()]
  def buys(%__MODULE__{orders: orders}) do
    Enum.filter(orders, &(&1.side == "B"))
  end

  @doc """
  Get sell orders.

  ## Parameters
    - `orders`: The frontend open orders struct

  ## Returns
    - List of sell orders
  """
  @spec sells(t()) :: [map()]
  def sells(%__MODULE__{orders: orders}) do
    Enum.filter(orders, &(&1.side == "A"))
  end

  @doc """
  Get orders for a specific coin.

  ## Parameters
    - `orders`: The frontend open orders struct
    - `coin`: Coin symbol

  ## Returns
    - List of orders for the coin
  """
  @spec by_coin(t(), String.t()) :: [map()]
  def by_coin(%__MODULE__{orders: orders}, coin) when is_binary(coin) do
    Enum.filter(orders, &(&1.coin == coin))
  end

  @doc """
  Get trigger orders only.

  ## Parameters
    - `orders`: The frontend open orders struct

  ## Returns
    - List of trigger orders
  """
  @spec trigger_orders(t()) :: [map()]
  def trigger_orders(%__MODULE__{orders: orders}) do
    Enum.filter(orders, &(&1.is_trigger == true))
  end

  @doc """
  Get reduce-only orders.

  ## Parameters
    - `orders`: The frontend open orders struct

  ## Returns
    - List of reduce-only orders
  """
  @spec reduce_only_orders(t()) :: [map()]
  def reduce_only_orders(%__MODULE__{orders: orders}) do
    Enum.filter(orders, &(&1.reduce_only == true))
  end

  @doc """
  Find order by OID.

  ## Parameters
    - `orders`: The frontend open orders struct
    - `oid`: Order ID

  ## Returns
    - `{:ok, Order.t()}` if found
    - `{:error, :not_found}` if not found
  """
  @spec find_by_oid(t(), integer()) :: {:ok, map()} | {:error, :not_found}
  def find_by_oid(%__MODULE__{orders: orders}, oid) when is_integer(oid) do
    case Enum.find(orders, &(&1.oid == oid)) do
      nil -> {:error, :not_found}
      order -> {:ok, order}
    end
  end

  @doc """
  Get total order count.

  ## Parameters
    - `orders`: The frontend open orders struct

  ## Returns
    - `non_neg_integer()`
  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{orders: orders}) do
    length(orders)
  end
end
