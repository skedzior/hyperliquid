defmodule Hyperliquid.Api.Info.MarginTable do
  @moduledoc """
  Margin table details.

  Returns margin requirements and leverage tiers.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint

  ## Usage

      {:ok, table} = MarginTable.request(0)
      max_lev = MarginTable.max_leverage_for_size(table, 100000.0)

      # HIP-3 builder perp dex
      {:ok, table} = MarginTable.request(0, dex: "test")
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "marginTable",
    params: [:id],
    # `dex` is optional; "" (or omitted) means the main dex. Added upstream in
    # @nktkas/hyperliquid v0.33.3 (249260c).
    optional_params: [:dex],
    rate_limit_cost: 1,
    doc: "Retrieve margin table details",
    returns: "Margin requirements and leverage tiers",
    storage: [
      postgres: [
        enabled: true,
        table: "margin_tables",
        # Upsert: id is the unique identifier
        conflict_target: :id,
        # Replace all fields on conflict
        on_conflict:
          {:replace,
           [
             :description,
             :margin_tiers,
             :updated_at
           ]}
      ],
      cache: [enabled: true],
      # Include id from request params
      context_params: [:id]
    ]

  @type t :: %__MODULE__{
          id: integer() | nil,
          description: String.t(),
          margin_tiers: [MarginTier.t()]
        }

  @primary_key false
  embedded_schema do
    # Margin table ID from request params
    field(:id, :integer)
    field(:description, :string)

    embeds_many :margin_tiers, MarginTier, primary_key: false do
      @moduledoc "Margin tier."

      field(:lower_bound, :string)
      field(:max_leverage, :integer)
    end
  end

  # ===================== Storage Extraction =====================

  @doc """
  Extract records for postgres insertion, converting margin_tiers embeds to JSONB.
  """
  def extract_records(data) do
    # Get id from context
    id = Map.get(data, :id) || Map.get(data, "id")

    # Convert margin_tiers to plain maps for JSONB storage
    margin_tiers =
      data
      |> Map.get(:margin_tiers, Map.get(data, "margin_tiers", []))
      |> Enum.map(fn
        %{__struct__: _} = tier -> Map.from_struct(tier) |> Map.drop([:__meta__])
        tier when is_map(tier) -> tier
      end)

    data
    |> Map.put(:id, id)
    |> Map.put(:margin_tiers, margin_tiers)
    |> List.wrap()
  end

  # ===================== Changesets =====================

  @doc """
  Creates a changeset for margin table data.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(table \\ %__MODULE__{}, attrs) do
    table
    |> cast(attrs, [:id, :description])
    |> cast_embed(:margin_tiers, with: &margin_tier_changeset/2)
  end

  defp margin_tier_changeset(tier, attrs) do
    tier
    |> cast(attrs, [:lower_bound, :max_leverage])
    |> validate_required([:lower_bound, :max_leverage])
  end

  # ===================== Helpers =====================

  @doc """
  Get max leverage for a position size.
  """
  @spec max_leverage_for_size(t(), float()) :: integer()
  def max_leverage_for_size(%__MODULE__{margin_tiers: tiers}, size) do
    tier =
      Enum.find(Enum.reverse(tiers), fn t ->
        String.to_float(t.lower_bound) <= size
      end)

    if tier, do: tier.max_leverage, else: 1
  end
end
