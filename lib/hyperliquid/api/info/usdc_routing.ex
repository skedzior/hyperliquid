defmodule Hyperliquid.Api.Info.UsdcRouting do
  @moduledoc """
  Current USDC deposit and withdrawal routing.

  Each route is either `"bridge"` (the native Arbitrum bridge) or `"cctp"`
  (Circle's Cross-Chain Transfer Protocol). The routes can change independently,
  so check the one for the direction you care about.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/usdc

  ## Usage

      {:ok, routing} = UsdcRouting.request()
      UsdcRouting.deposit_via_cctp?(routing)
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request: %{type: "usdcRouting"},
    rate_limit_cost: 2,
    doc: "Retrieve current USDC deposit and withdrawal routing",
    returns: "Deposit and withdrawal routes, each bridge or cctp",
    storage: [
      cache: [
        enabled: true,
        ttl: :timer.minutes(1),
        key_pattern: "usdc_routing"
      ]
    ]

  @routes ~w(bridge cctp)

  @type route :: String.t()

  @type t :: %__MODULE__{
          deposit_route: route() | nil,
          withdrawal_route: route() | nil
        }

  @primary_key false
  embedded_schema do
    field(:deposit_route, :string)
    field(:withdrawal_route, :string)
  end

  # ===================== Changesets =====================

  @doc """
  Creates a changeset for USDC routing data.

  ## Parameters
    - `routing`: The routing struct
    - `attrs`: Map of attributes

  ## Returns
    - `Ecto.Changeset.t()`
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(routing \\ %__MODULE__{}, attrs) do
    routing
    |> cast(attrs, [:deposit_route, :withdrawal_route])
    |> validate_inclusion(:deposit_route, @routes)
    |> validate_inclusion(:withdrawal_route, @routes)
  end

  # ===================== Helpers =====================

  @doc """
  Known routing values.

  ## Returns
    - List of valid route strings
  """
  @spec routes() :: [route()]
  def routes, do: @routes

  @doc """
  Whether deposits currently route over CCTP.

  ## Parameters
    - `routing`: The routing struct

  ## Returns
    - `boolean()`
  """
  @spec deposit_via_cctp?(t()) :: boolean()
  def deposit_via_cctp?(%__MODULE__{deposit_route: "cctp"}), do: true
  def deposit_via_cctp?(%__MODULE__{}), do: false

  @doc """
  Whether withdrawals currently route over CCTP.

  ## Parameters
    - `routing`: The routing struct

  ## Returns
    - `boolean()`
  """
  @spec withdrawal_via_cctp?(t()) :: boolean()
  def withdrawal_via_cctp?(%__MODULE__{withdrawal_route: "cctp"}), do: true
  def withdrawal_via_cctp?(%__MODULE__{}), do: false
end
