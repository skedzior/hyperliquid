defmodule Hyperliquid.Api.Common do
  @moduledoc """
  Common schemas used across multiple Hyperliquid API endpoints.

  Auto-generated from @nktkas/hyperliquid v0.26.0
  Source: src/api/_common_schemas.ts

  This module contains Ecto embedded schemas for types that are reused
  across different API endpoints, including:

  - Balance (spot token balances)
  - DetailedOrder (open orders with frontend info)
  - TwapState (TWAP order state)
  - TIF (time-in-force enum)
  - OrderSchema (basic order details)
  """

  use Ecto.Schema
  import Ecto.Changeset

  # ===================== Balance Schema =====================

  @typedoc """
  Balance for a specific spot token.
  """
  @type balance :: %__MODULE__.Balance{}

  defmodule Balance do
    @moduledoc """
    Balance for a specific spot token.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:coin, :string)
      field(:token, :integer)
      field(:total, :string)
      field(:hold, :string)
      field(:entry_ntl, :string)
    end

    def changeset(balance \\ %__MODULE__{}, attrs) do
      balance
      |> cast(attrs, [:coin, :token, :total, :hold, :entry_ntl])
      |> validate_required([:coin, :token, :total, :hold, :entry_ntl])
    end
  end

  # ===================== Detailed Order Schema =====================

  @typedoc """
  Open order with display information.
  """
  @type detailed_order :: %__MODULE__.DetailedOrder{}

  defmodule DetailedOrder do
    @moduledoc """
    Open order with additional display information.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
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

    def changeset(order \\ %__MODULE__{}, attrs) do
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
      |> validate_required([
        :coin,
        :side,
        :limit_px,
        :sz,
        :oid,
        :timestamp,
        :orig_sz,
        :trigger_condition,
        :is_trigger,
        :is_position_tpsl,
        :reduce_only,
        :order_type
      ])
      |> validate_inclusion(:side, ["B", "A"])
    end
  end

  # ===================== TWAP State Schema =====================

  @typedoc """
  State of a TWAP order.
  """
  @type twap_state :: %__MODULE__.TwapState{}

  defmodule TwapState do
    @moduledoc """
    State of the TWAP order.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:coin, :string)
      field(:executed_ntl, :string)
      field(:executed_sz, :string)
      field(:minutes, :integer)
      field(:randomize, :boolean)
      field(:reduce_only, :boolean)
      field(:side, :string)
      field(:sz, :string)
      field(:timestamp, :integer)
      field(:user, :string)
    end

    def changeset(state \\ %__MODULE__{}, attrs) do
      state
      |> cast(attrs, [
        :coin,
        :executed_ntl,
        :executed_sz,
        :minutes,
        :randomize,
        :reduce_only,
        :side,
        :sz,
        :timestamp,
        :user
      ])
      |> validate_required([
        :coin,
        :executed_ntl,
        :executed_sz,
        :minutes,
        :randomize,
        :reduce_only,
        :side,
        :sz,
        :timestamp,
        :user
      ])
      |> validate_inclusion(:side, ["B", "A"])
      |> validate_format(:user, ~r/^0x[0-9a-fA-F]{40}$/)
    end
  end

  # ===================== Helper Functions =====================

  @doc """
  Parse Balance data from API response.
  """
  def parse_balance(data) when is_map(data) do
    data
    |> snake_case_keys()
    |> then(&Balance.changeset(%Balance{}, &1))
    |> apply_action(:validate)
  end

  @doc """
  Parse DetailedOrder data from API response.
  """
  def parse_detailed_order(data) when is_map(data) do
    data
    |> snake_case_keys()
    |> then(&DetailedOrder.changeset(%DetailedOrder{}, &1))
    |> apply_action(:validate)
  end

  @doc """
  Parse TwapState data from API response.
  """
  def parse_twap_state(data) when is_map(data) do
    data
    |> snake_case_keys()
    |> then(&TwapState.changeset(%TwapState{}, &1))
    |> apply_action(:validate)
  end

  # ===================== Private Helpers =====================

  defp snake_case_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_snake_case(k), v} end)
    |> Enum.into(%{})
  end

  defp to_snake_case(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> to_snake_case()
    |> String.to_atom()
  end

  # Single-character keys have no word boundary to split on. Macro.underscore/1
  # downcases them ("T" -> "t"), which would collapse distinct sibling keys into
  # one and silently drop a field. Pass them through unchanged.
  defp to_snake_case(<<_::utf8>> = key), do: key

  defp to_snake_case(key) when is_binary(key) do
    Macro.underscore(key)
  end
end
