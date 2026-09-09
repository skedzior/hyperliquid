defmodule Hyperliquid.Api.Info.VaultDetails do
  @moduledoc """
  Detailed vault information.

  Returns comprehensive details about a specific vault, or `nil` when the vault
  address does not exist (`request/1` answers `{:ok, nil}` in that case).

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint#retrieve-details-for-a-vault
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "vaultDetails",
    params: [:vaultAddress],
    optional_params: [:user],
    rate_limit_cost: 1,
    doc: "Retrieve detailed vault information",
    returns: "Comprehensive details about a specific vault"

  alias Hyperliquid.Transport.Http

  @type t :: %__MODULE__{
          name: String.t(),
          vault_address: String.t(),
          leader: String.t(),
          description: String.t(),
          portfolio: list(),
          apr: float(),
          follower_state: map() | nil,
          leader_fraction: float(),
          leader_commission: float(),
          followers: list(),
          max_distributable: float(),
          max_withdrawable: float(),
          is_closed: boolean(),
          relationship: map(),
          allow_deposits: boolean(),
          always_close_on_withdraw: boolean()
        }

  @primary_key false
  embedded_schema do
    field(:name, :string)
    field(:vault_address, :string)
    field(:leader, :string)
    field(:description, :string)
    # Complex nested structure - use :any to avoid cast errors
    field(:portfolio, {:array, :any})
    field(:apr, :float)
    field(:follower_state, :map)
    field(:leader_fraction, :float)
    field(:leader_commission, :float)
    # Complex nested structure with nested arrays
    field(:followers, {:array, :any})
    field(:max_distributable, :float)
    field(:max_withdrawable, :float)
    field(:is_closed, :boolean)
    field(:relationship, :map)
    field(:allow_deposits, :boolean)
    field(:always_close_on_withdraw, :boolean)
  end

  # ===================== Preprocessing =====================

  @doc false
  # The API returns `null` for a non-existent vault (nktkas v0.33.3 widened
  # `VaultDetailsResponse` to `{...} | null`). Pass the nil straight through so
  # `parse_response/1` can answer `{:ok, nil}` instead of failing the changeset.
  def preprocess(nil), do: nil

  def preprocess(data) when is_map(data), do: data
  def preprocess(data), do: data

  # ===================== Response Parsing =====================

  @doc """
  Parse and validate the API response.

  Returns `{:ok, nil}` when the vault does not exist (the API answers `null`).
  """
  @spec parse_response(map() | nil) :: {:ok, t() | nil} | {:error, term()}
  def parse_response(nil), do: {:ok, nil}

  def parse_response(data) when is_map(data) and map_size(data) == 0, do: {:ok, nil}

  def parse_response(data) when is_map(data) do
    changeset(%__MODULE__{}, data)
    |> apply_action(:validate)
  end

  def parse_response(_), do: {:error, :invalid_response_format}

  # ===================== Custom Request Methods =====================

  @doc """
  Build the request payload with optional user parameter.

  ## Parameters
    - `vault_address`: Vault address (0x...)
    - `user`: Optional user address to get follower state

  ## Returns
    - Map with request parameters
  """
  @spec build_request_with_user(String.t(), String.t()) :: map()
  def build_request_with_user(vault_address, user) when is_binary(user) do
    %{type: "vaultDetails", vaultAddress: vault_address, user: user}
  end

  @doc """
  Fetches vault details with optional user parameter.

  ## Parameters
    - `vault_address`: Vault address (0x...)
    - `user`: Optional user address to get follower state

  ## Returns
    - `{:ok, %VaultDetails{}}` - Parsed and validated data
    - `{:error, term()}` - Error from HTTP or validation

  ## Example

      {:ok, details} = VaultDetails.request_with_user("0x1234...", "0x5678...")
  """
  @spec request_with_user(String.t(), String.t() | nil) :: {:ok, t()} | {:error, term()}
  def request_with_user(vault_address, user) when is_binary(user) do
    with {:ok, data} <- Http.info_request(build_request_with_user(vault_address, user)),
         {:ok, result} <- parse_response(data) do
      {:ok, result}
    end
  end

  # ===================== Changesets =====================

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(details \\ %__MODULE__{}, attrs) do
    details
    |> cast(attrs, [
      :name,
      :vault_address,
      :leader,
      :description,
      :portfolio,
      :apr,
      :follower_state,
      :leader_fraction,
      :leader_commission,
      :followers,
      :max_distributable,
      :max_withdrawable,
      :is_closed,
      :relationship,
      :allow_deposits,
      :always_close_on_withdraw
    ])
    |> validate_required([:name, :vault_address, :leader])
  end

  # ===================== Helpers =====================

  @doc """
  Check if vault is closed.
  """
  @spec closed?(t()) :: boolean()
  def closed?(%__MODULE__{is_closed: is_closed}), do: is_closed == true

  @doc """
  Check if deposits are allowed.
  """
  @spec deposits_allowed?(t()) :: boolean()
  def deposits_allowed?(%__MODULE__{allow_deposits: allow}), do: allow == true
end
