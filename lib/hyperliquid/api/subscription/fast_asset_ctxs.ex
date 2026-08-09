defmodule Hyperliquid.Api.Subscription.FastAssetCtxs do
  @moduledoc """
  WebSocket subscription for low-latency mark and mid price updates.

  A trimmed-down counterpart to `assetCtxs`: each event is a map of coin to a
  context carrying only `markPx` and `midPx`, either of which may be absent, and
  `midPx` may be explicitly null when there is no two-sided market.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/subscriptions

  ## Usage

      {:ok, request} = FastAssetCtxs.build_request()
      # => {:ok, %{type: "fastAssetCtxs"}}
  """

  use Hyperliquid.Api.SubscriptionEndpoint,
    request_type: "fastAssetCtxs",
    connection_type: :shared,
    doc: "Low-latency mark and mid prices - can share connection"

  @type t :: %__MODULE__{ctxs: map()}

  @primary_key false
  embedded_schema do
    # %{coin => %{"markPx" => String.t(), "midPx" => String.t() | nil}}
    field(:ctxs, :map)
  end

  # ===================== Preprocessing =====================

  @doc false
  # The event is a bare coin-keyed object; nest it so it fits the schema.
  def preprocess(data) when is_map(data) and not is_struct(data) do
    case data do
      %{ctxs: _} -> data
      %{"ctxs" => _} -> data
      _ -> %{ctxs: data}
    end
  end

  def preprocess(data), do: data

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event \\ %__MODULE__{}, attrs) do
    cast(event, attrs, [:ctxs])
  end

  # ===================== Helpers =====================

  @doc """
  Mark price for a coin.

  ## Parameters
    - `event`: The subscription event
    - `coin`: Coin name

  ## Returns
    - `{:ok, String.t()}` if present
    - `{:error, :not_found}` otherwise
  """
  @spec mark_px(t() | map(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def mark_px(event, coin), do: fetch_px(event, coin, "markPx")

  @doc """
  Mid price for a coin.

  Returns `{:error, :not_found}` when the coin has no mid price, which includes
  the case where the API sent an explicit null.

  ## Parameters
    - `event`: The subscription event
    - `coin`: Coin name

  ## Returns
    - `{:ok, String.t()}` if present
    - `{:error, :not_found}` otherwise
  """
  @spec mid_px(t() | map(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def mid_px(event, coin), do: fetch_px(event, coin, "midPx")

  @doc """
  Coins present in this event.

  ## Parameters
    - `event`: The subscription event

  ## Returns
    - List of coin names
  """
  @spec coins(t() | map()) :: [String.t()]
  def coins(%__MODULE__{ctxs: ctxs}) when is_map(ctxs), do: Map.keys(ctxs)
  def coins(%{ctxs: ctxs}) when is_map(ctxs), do: Map.keys(ctxs)
  def coins(_), do: []

  defp fetch_px(event, coin, key) do
    ctxs =
      case event do
        %__MODULE__{ctxs: ctxs} -> ctxs
        %{ctxs: ctxs} -> ctxs
        _ -> nil
      end

    with true <- is_map(ctxs),
         ctx when is_map(ctx) <- Map.get(ctxs, coin),
         value when is_binary(value) <- Map.get(ctx, key) do
      {:ok, value}
    else
      _ -> {:error, :not_found}
    end
  end
end
