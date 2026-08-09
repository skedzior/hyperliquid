defmodule Hyperliquid.Api.Info.OutcomeTemplates do
  @moduledoc """
  Templates that HIP-4 outcome deployers instantiate.

  Every deployer-created prediction market comes from a template. A template
  fixes display name and description text containing `{keyword}` placeholders,
  together with a typed hint per keyword; an instantiation supplies exactly one
  value per keyword.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/hip-4-deployer-actions

  ## Usage

      {:ok, templates} = OutcomeTemplates.request()
      {:ok, template} = OutcomeTemplates.find(templates, "some-template-id")
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request: %{type: "outcomeTemplates"},
    rate_limit_cost: 2,
    doc: "Retrieve HIP-4 outcome templates",
    returns: "Templates that outcome deployers instantiate",
    storage: [
      cache: [
        enabled: true,
        ttl: :timer.minutes(30),
        key_pattern: "outcome_templates"
      ]
    ]

  @typedoc """
  Value format required for a template keyword.

  - `"dateTime"` - `%Y%m%d-%H%M`, within the next year (e.g. `20260712-1830`)
  - `"date"` - `YYYYMMDD`, end of day, within the next year (e.g. `20260712`)
  - `"string"` - free text
  - `"hlPerp"` - coin name of an existing perp (e.g. `ABC` or `test:ABC`)
  """
  @type keyword_hint :: String.t()

  @type t :: %__MODULE__{templates: [map()]}

  @primary_key false
  embedded_schema do
    embeds_many :templates, Template, primary_key: false do
      @moduledoc "A single outcome template."

      field(:id, :string)
      # %{"standaloneOutcome" => %{"sideNames" => [yes, no]}} and friends
      field(:role, :map)
      field(:name, :string)
      field(:description, :string)
      # [[keyword, hint], ...] kept as raw tuples
      field(:keywords, {:array, :any})
    end
  end

  # ===================== Preprocessing =====================

  @doc false
  def preprocess(data) when is_list(data), do: %{templates: data}
  def preprocess(data), do: data

  # ===================== Changesets =====================

  @doc """
  Creates a changeset for outcome templates.

  ## Parameters
    - `templates`: The templates struct
    - `attrs`: Map with a templates key

  ## Returns
    - `Ecto.Changeset.t()`
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(templates \\ %__MODULE__{}, attrs) do
    templates
    |> cast(attrs, [])
    |> cast_embed(:templates, with: &template_changeset/2)
  end

  defp template_changeset(template, attrs) do
    template
    |> cast(attrs, [:id, :role, :name, :description, :keywords])
    |> validate_required([:id])
  end

  # ===================== Helpers =====================

  @doc """
  Find a template by id.

  ## Parameters
    - `templates`: The templates struct
    - `id`: Template identifier

  ## Returns
    - `{:ok, template}` if found
    - `{:error, :not_found}` otherwise
  """
  @spec find(t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def find(%__MODULE__{templates: templates}, id) when is_binary(id) do
    case Enum.find(templates, &(&1.id == id)) do
      nil -> {:error, :not_found}
      template -> {:ok, template}
    end
  end

  @doc """
  List the keyword names a template requires, in the order the API returned them.

  `keywordToValue` must be sorted lexicographically before signing, so use
  `keyword_names/1` to discover the keywords and sort your own pairs.

  ## Parameters
    - `template`: A template from the response

  ## Returns
    - List of keyword names
  """
  @spec keyword_names(map()) :: [String.t()]
  def keyword_names(%{keywords: keywords}) when is_list(keywords) do
    Enum.map(keywords, fn
      [name, _hint] -> name
      {name, _hint} -> name
      name when is_binary(name) -> name
    end)
  end

  def keyword_names(_), do: []

  @doc """
  Build the sorted `keywordToValue` list required by the deploy actions.

  The exchange requires lists of tuples to be lexicographically sorted before
  signing.

  ## Parameters
    - `values`: Map or keyword list of keyword name to value

  ## Returns
    - Sorted list of `[keyword, value]` pairs

  ## Examples

      iex> Hyperliquid.Api.Info.OutcomeTemplates.keyword_to_value(%{
      ...>   "underlying" => "ABC",
      ...>   "expiry" => "20260801-0600",
      ...>   "target" => "100"
      ...> })
      [["expiry", "20260801-0600"], ["target", "100"], ["underlying", "ABC"]]
  """
  @spec keyword_to_value(map() | keyword()) :: [[String.t()]]
  def keyword_to_value(values) do
    values
    |> Enum.map(fn {k, v} -> [to_string(k), to_string(v)] end)
    |> Enum.sort_by(fn [k, _v] -> k end)
  end
end
