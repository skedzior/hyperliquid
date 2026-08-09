defmodule Hyperliquid.Api.Info.GossipPriorityAuctionStatus do
  @moduledoc """
  Status of the gossip priority slot auctions.

  The response is a two-element array: the IPs currently holding each priority
  slot (`nil` for an unclaimed slot), and the auction status for each slot in the
  same shape as `perpDeployAuctionStatus`.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/priority-fees

  ## Usage

      {:ok, status} = GossipPriorityAuctionStatus.request()
      GossipPriorityAuctionStatus.slot_holders(status)
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request: %{type: "gossipPriorityAuctionStatus"},
    rate_limit_cost: 2,
    doc: "Retrieve gossip priority slot auction status",
    returns: "Current slot holders and per-slot auction status",
    storage: [
      cache: [
        enabled: true,
        ttl: :timer.seconds(30),
        key_pattern: "gossip_priority_auction_status"
      ]
    ]

  @type t :: %__MODULE__{
          slot_holders: [String.t() | nil],
          auctions: [map()]
        }

  @primary_key false
  embedded_schema do
    # One entry per slot; nil when the slot is unclaimed.
    field(:slot_holders, {:array, :string})
    field(:auctions, {:array, :map})
  end

  # ===================== Preprocessing =====================

  @doc false
  def preprocess([holders, auctions]) when is_list(holders) and is_list(auctions) do
    %{slot_holders: holders, auctions: auctions}
  end

  def preprocess(data), do: data

  # ===================== Changesets =====================

  @doc """
  Creates a changeset for auction status data.

  ## Parameters
    - `status`: The auction status struct
    - `attrs`: Map with slot_holders and auctions keys

  ## Returns
    - `Ecto.Changeset.t()`
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(status \\ %__MODULE__{}, attrs) do
    cast(status, attrs, [:slot_holders, :auctions])
  end

  # ===================== Helpers =====================

  @doc """
  IPs currently holding a priority slot, indexed by slot id.

  ## Parameters
    - `status`: The auction status struct

  ## Returns
    - List where each element is an IP string or nil
  """
  @spec slot_holders(t()) :: [String.t() | nil]
  def slot_holders(%__MODULE__{slot_holders: holders}) when is_list(holders), do: holders
  def slot_holders(%__MODULE__{}), do: []

  @doc """
  Whether a given slot is currently unclaimed.

  ## Parameters
    - `status`: The auction status struct
    - `slot_id`: Slot identifier

  ## Returns
    - `boolean()`
  """
  @spec slot_available?(t(), non_neg_integer()) :: boolean()
  def slot_available?(%__MODULE__{} = status, slot_id) when is_integer(slot_id) do
    status |> slot_holders() |> Enum.at(slot_id) |> is_nil()
  end

  @doc """
  Auction status for a given slot.

  ## Parameters
    - `status`: The auction status struct
    - `slot_id`: Slot identifier

  ## Returns
    - `{:ok, auction}` if present
    - `{:error, :not_found}` otherwise
  """
  @spec auction_for(t(), non_neg_integer()) :: {:ok, map()} | {:error, :not_found}
  def auction_for(%__MODULE__{auctions: auctions}, slot_id)
      when is_list(auctions) and is_integer(slot_id) do
    case Enum.at(auctions, slot_id) do
      nil -> {:error, :not_found}
      auction -> {:ok, auction}
    end
  end

  def auction_for(%__MODULE__{}, _slot_id), do: {:error, :not_found}
end
