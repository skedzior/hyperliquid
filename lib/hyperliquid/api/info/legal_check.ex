defmodule Hyperliquid.Api.Info.LegalCheck do
  @moduledoc """
  Legal/compliance check for a user.

  Returns whether a user is allowed to use the platform based on jurisdiction.

  The `restrictions` field is a single-letter code:

  - `"n"` - no restrictions
  - `"a"` - platform actions blocked
  - `"o"` - outcome markets hidden
  - `"u"` - restricted as a UK user

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "legalCheck",
    params: [:user],
    rate_limit_cost: 1,
    doc: "Check legal/compliance status for a user",
    returns: "Whether user is allowed to use the platform based on jurisdiction"

  @type t :: %__MODULE__{
          ip_allowed: boolean(),
          accepted_terms: boolean(),
          user_allowed: boolean(),
          restrictions: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field(:ip_allowed, :boolean)
    field(:accepted_terms, :boolean)
    field(:user_allowed, :boolean)
    # Restriction code; see `restriction_description/1`.
    field(:restrictions, :string)
  end

  @restrictions %{
    "n" => "no restrictions",
    "a" => "platform actions blocked",
    "o" => "outcome markets hidden",
    "u" => "restricted as UK user"
  }

  # ===================== Changesets =====================

  @doc """
  Creates a changeset for legal check data.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(check \\ %__MODULE__{}, attrs) do
    check
    |> cast(attrs, [:ip_allowed, :accepted_terms, :user_allowed, :restrictions])
    |> validate_required([:ip_allowed, :accepted_terms, :user_allowed])
  end

  @doc """
  Map of restriction codes to human-readable descriptions.

  `restrictions` is required in `@nktkas/hyperliquid` v0.33.3 (it used to be
  optional); it is left optional here so older cached payloads still cast.
  """
  @spec restrictions() :: %{String.t() => String.t()}
  def restrictions, do: @restrictions

  @doc """
  Human-readable description for a restriction code.

      iex> Hyperliquid.Api.Info.LegalCheck.restriction_description("o")
      "outcome markets hidden"
  """
  @spec restriction_description(String.t() | nil) :: String.t() | nil
  def restriction_description(code), do: Map.get(@restrictions, code)

  @doc "True when the user carries no jurisdiction restriction (`\"n\"` or absent)."
  @spec unrestricted?(t()) :: boolean()
  def unrestricted?(%__MODULE__{restrictions: r}), do: r in [nil, "n"]

  @doc "True when HIP-4 outcome markets must be hidden from this user."
  @spec outcome_markets_hidden?(t()) :: boolean()
  def outcome_markets_hidden?(%__MODULE__{restrictions: r}), do: r == "o"

  @doc """
  Check if user is fully allowed (IP, terms, and user all allowed).
  """
  @spec allowed?(t()) :: boolean()
  def allowed?(%__MODULE__{ip_allowed: ip, accepted_terms: terms, user_allowed: user}) do
    ip == true and terms == true and user == true
  end

  @doc """
  Check if IP is allowed.
  """
  @spec ip_allowed?(t()) :: boolean()
  def ip_allowed?(%__MODULE__{ip_allowed: allowed}), do: allowed == true
end
