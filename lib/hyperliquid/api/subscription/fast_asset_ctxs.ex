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

  # Negative window bits select raw DEFLATE (no zlib header).
  @raw_deflate_window_bits -15

  @type t :: %__MODULE__{ctxs: map()}

  @primary_key false
  embedded_schema do
    # %{coin => %{"markPx" => String.t(), "midPx" => String.t() | nil}}
    field(:ctxs, :map)
  end

  # ===================== Preprocessing =====================

  @doc false
  # The server pushes each event as a base64 + raw-DEFLATE (RFC 1951) compressed
  # JSON string, so a binary payload is decompressed before anything else. This
  # matches `@nktkas/hyperliquid`'s `fastAssetCtxs` listener, which decompresses
  # with `DecompressionStream("deflate-raw")`.
  def preprocess(payload) when is_binary(payload) do
    case decode(payload) do
      {:ok, decoded} -> preprocess(decoded)
      {:error, _reason} -> payload
    end
  end

  # The decoded event is a bare coin-keyed object; nest it so it fits the schema.
  def preprocess(data) when is_map(data) and not is_struct(data) do
    case data do
      %{ctxs: _} -> data
      %{"ctxs" => _} -> data
      _ -> %{ctxs: data}
    end
  end

  def preprocess(data), do: data

  @doc """
  Decode a base64 + raw-DEFLATE `fastAssetCtxs` payload into its coin-keyed map.

  ## Returns
    - `{:ok, map()}`
    - `{:error, :invalid_base64 | :inflate_failed | {:json_decode_error, term()}}`
  """
  @spec decode(binary()) :: {:ok, map()} | {:error, term()}
  def decode(payload) when is_binary(payload) do
    with {:ok, compressed} <- decode_base64(payload),
         {:ok, json} <- inflate_raw(compressed) do
      case Jason.decode(json) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, reason} -> {:error, {:json_decode_error, reason}}
      end
    end
  end

  @doc """
  Inflate a raw DEFLATE (RFC 1951, no zlib header) stream.
  """
  @spec inflate_raw(binary()) :: {:ok, binary()} | {:error, :inflate_failed}
  def inflate_raw(compressed) when is_binary(compressed) do
    z = :zlib.open()

    try do
      :zlib.inflateInit(z, @raw_deflate_window_bits)
      inflated = :zlib.inflate(z, compressed)
      :zlib.inflateEnd(z)
      {:ok, IO.iodata_to_binary(inflated)}
    rescue
      _ -> {:error, :inflate_failed}
    catch
      _, _ -> {:error, :inflate_failed}
    after
      :zlib.close(z)
    end
  end

  defp decode_base64(payload) do
    case Base.decode64(payload) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :invalid_base64}
    end
  end

  @doc """
  Merge an incremental event into an accumulated coin-keyed snapshot.

  The first message on the channel is a full snapshot; later messages carry only
  the coins that changed.
  """
  @spec merge(map(), t() | map()) :: map()
  def merge(snapshot, event) when is_map(snapshot) do
    Map.merge(snapshot, unwrap_ctxs(event))
  end

  defp unwrap_ctxs(%__MODULE__{ctxs: ctxs}) when is_map(ctxs), do: ctxs
  defp unwrap_ctxs(%{ctxs: ctxs}) when is_map(ctxs), do: ctxs
  defp unwrap_ctxs(%{"ctxs" => ctxs}) when is_map(ctxs), do: ctxs
  defp unwrap_ctxs(event) when is_map(event), do: event

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
