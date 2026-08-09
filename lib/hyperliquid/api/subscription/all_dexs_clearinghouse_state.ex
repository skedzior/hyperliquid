defmodule Hyperliquid.Api.Subscription.AllDexsClearinghouseState do
  @moduledoc """
  WebSocket subscription for a user's clearinghouse state across all DEXes.

  Shares the connection with other user-grouped subscriptions for the same
  address. Equivalent to `clearinghouseState` but aggregated across all DEXes.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/subscriptions
  """

  use Hyperliquid.Api.SubscriptionEndpoint,
    request_type: "allDexsClearinghouseState",
    params: [:user],
    connection_type: :user_grouped,
    doc: "Clearinghouse state across all DEXes per user - shares connection per user",
    key_fields: [:user]

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:user, :string)
    field(:margin_summary, :map)
    field(:cross_margin_summary, :map)
    field(:withdrawable, :string)
    field(:asset_positions, {:array, :map})
    field(:dex_states, {:array, :map})
  end

  @spec build_request(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def build_request(params) do
    types = %{user: :string}

    changeset =
      {%{}, types}
      |> cast(params, Map.keys(types))
      |> validate_required([:user])
      |> validate_format(:user, ~r/^0x[0-9a-fA-F]{40}$/)

    if changeset.valid? do
      {:ok, %{type: "allDexsClearinghouseState", user: get_change(changeset, :user)}}
    else
      {:error, changeset}
    end
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event \\ %__MODULE__{}, attrs) do
    event
    |> cast(attrs, [
      :user,
      :margin_summary,
      :cross_margin_summary,
      :withdrawable,
      :asset_positions,
      :dex_states
    ])
  end
end
