defmodule Hyperliquid.Api.Subscription.AllDexsAssetCtxs do
  @moduledoc """
  WebSocket subscription for asset contexts across all DEXes.

  Global broadcast with no user parameter — equivalent to `assetCtxs` but
  covering all DEXes rather than only the default Hyperliquid DEX.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/subscriptions
  """

  use Hyperliquid.Api.SubscriptionEndpoint,
    request_type: "allDexsAssetCtxs",
    params: [],
    connection_type: :shared,
    doc: "Asset contexts across all DEXes - global broadcast, can share connection"

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:meta, :map)
    field(:asset_ctxs, {:array, :map})
    field(:dex, :string)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event \\ %__MODULE__{}, attrs) do
    event
    |> cast(attrs, [:meta, :asset_ctxs, :dex])
  end
end
