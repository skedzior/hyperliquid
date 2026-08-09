defmodule Hyperliquid.Api.Subscription.ClearinghouseState do
  @moduledoc """
  WebSocket subscription for user's clearinghouse state.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/subscriptions
  """

  use Hyperliquid.Api.SubscriptionEndpoint,
    request_type: "clearinghouseState",
    params: [:user],
    optional_params: [:dex],
    connection_type: :user_grouped,
    doc: "Clearinghouse state - shares connection per user",
    storage: [
      postgres: [
        enabled: true,
        table: "clearinghouse_states"
      ],
      cache: [
        enabled: true,
        key_pattern: "clearinghouse:{{user}}"
      ]
    ]

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:user, :string)
    field(:dex, :string)
    field(:margin_summary, :map)
    field(:cross_margin_summary, :map)
    field(:withdrawable, :string)
    field(:asset_positions, {:array, :map})
  end

  @spec build_request(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def build_request(params) do
    types = %{user: :string, dex: :string}

    changeset =
      {%{}, types}
      |> cast(params, Map.keys(types))
      |> validate_required([:user])
      |> validate_format(:user, ~r/^0x[0-9a-fA-F]{40}$/)

    if changeset.valid? do
      {:ok,
       %{
         type: "clearinghouseState",
         user: get_change(changeset, :user),
         # "" is the documented default for the main perps dex. Ecto treats it
         # as an empty value, so it never lands in changes — fall back to it.
         dex: get_change(changeset, :dex) || ""
       }}
    else
      {:error, changeset}
    end
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event \\ %__MODULE__{}, attrs) do
    event
    |> cast(attrs, [
      :user,
      :dex,
      :margin_summary,
      :cross_margin_summary,
      :withdrawable,
      :asset_positions
    ])
  end
end
