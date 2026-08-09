defmodule Hyperliquid.Api.Info.PerpConciseAnnotations do
  @moduledoc """
  Concise category annotations for perp coins.

  The API returns `[coin, annotation]` pairs; this module reshapes them into a
  list of annotation records keyed by coin.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint/perpetuals

  ## Usage

      {:ok, annotations} = PerpConciseAnnotations.request()
      {:ok, btc} = PerpConciseAnnotations.find(annotations, "BTC")
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request: %{type: "perpConciseAnnotations"},
    rate_limit_cost: 2,
    doc: "Retrieve concise category annotations for perp coins",
    returns: "Per-coin category, display name and keywords",
    storage: [
      cache: [
        enabled: true,
        ttl: :timer.minutes(30),
        key_pattern: "perp_concise_annotations"
      ]
    ]

  @type t :: %__MODULE__{annotations: [map()]}

  @primary_key false
  embedded_schema do
    embeds_many :annotations, Annotation, primary_key: false do
      @moduledoc "Annotation for a single perp coin."

      field(:coin, :string)
      field(:category, :string)
      field(:display_name, :string)
      field(:keywords, {:array, :string})
    end
  end

  # ===================== Preprocessing =====================

  @doc false
  def preprocess(data) when is_list(data) do
    annotations =
      Enum.flat_map(data, fn
        [coin, annotation] when is_map(annotation) ->
          [Map.put(annotation, "coin", coin)]

        _ ->
          []
      end)

    %{annotations: annotations}
  end

  def preprocess(data), do: data

  # ===================== Changesets =====================

  @doc """
  Creates a changeset for perp annotations.

  ## Parameters
    - `annotations`: The annotations struct
    - `attrs`: Map with an annotations key

  ## Returns
    - `Ecto.Changeset.t()`
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(annotations \\ %__MODULE__{}, attrs) do
    annotations
    |> cast(attrs, [])
    |> cast_embed(:annotations, with: &annotation_changeset/2)
  end

  defp annotation_changeset(annotation, attrs) do
    annotation
    |> cast(attrs, [:coin, :category, :display_name, :keywords])
    |> validate_required([:coin])
  end

  # ===================== Helpers =====================

  @doc """
  Find the annotation for a coin.

  ## Parameters
    - `annotations`: The annotations struct
    - `coin`: Coin name

  ## Returns
    - `{:ok, annotation}` if found
    - `{:error, :not_found}` otherwise
  """
  @spec find(t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def find(%__MODULE__{annotations: annotations}, coin) when is_binary(coin) do
    case Enum.find(annotations, &(&1.coin == coin)) do
      nil -> {:error, :not_found}
      annotation -> {:ok, annotation}
    end
  end

  @doc """
  Group coins by their category.

  ## Parameters
    - `annotations`: The annotations struct

  ## Returns
    - Map of category to list of coin names
  """
  @spec by_category(t()) :: %{optional(String.t()) => [String.t()]}
  def by_category(%__MODULE__{annotations: annotations}) do
    annotations
    |> Enum.reject(&is_nil(&1.category))
    |> Enum.group_by(& &1.category, & &1.coin)
  end

  @doc """
  List the distinct categories present.

  ## Parameters
    - `annotations`: The annotations struct

  ## Returns
    - Sorted list of category names
  """
  @spec categories(t()) :: [String.t()]
  def categories(%__MODULE__{} = annotations) do
    annotations |> by_category() |> Map.keys() |> Enum.sort()
  end
end
