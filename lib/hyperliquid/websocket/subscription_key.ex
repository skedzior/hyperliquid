defmodule Hyperliquid.WebSocket.SubscriptionKey do
  @moduledoc """
  Canonical subscription identity and routing keys for the WebSocket layer.

  A Hyperliquid WS connection multiplexes many subscriptions. Frames only carry
  the channel name plus whichever discriminating fields the server echoes, so
  routing has to be done on the *full* subscription identity — channel **plus**
  `coin` / `user` / `interval` / `dex` — never on the channel alone. Dispatching
  on channel only makes a BTC `l2Book` subscriber receive ETH books.

  This module is the single source of truth used by subscribe, unsubscribe and
  dispatch:

    * `identity/2` — the exact identity of a subscription (channel + every
      declared key field, including fields the server never echoes such as
      `nSigFigs`). Used for de-duplication and unsubscribe.
    * `routing_key/2` — the identity restricted to fields the server actually
      echoes. Used as the dispatch key.
    * `matches?/2` — does an inbound frame belong to this subscription?

  ## Channel groups

  Derived from the empirical subscription map in
  `docs/hl-api-rate-limits-and-ws-subscription-map.md`:

    * **Group A** (`notification`, `orderUpdates`, `userEvents`) — events carry
      *no* user attribution. Two users of these channels on one connection are
      indistinguishable, so the connection packer allows at most one Group A
      user per connection.
    * **Group B** — user channels that echo `user` (and sometimes `coin`/`dex`).
      Safe to multiplex up to the per-connection unique-user cap.
    * **Group C** — market channels that echo their key (`coin`, `s`+`i`, `dex`).
    * **Group D** — parameterless broadcast channels.
  """

  @type t :: %__MODULE__{
          module: module() | nil,
          channel: String.t(),
          fields: %{atom() => String.t()}
        }

  defstruct module: nil, channel: "", fields: %{}

  # Channels whose events carry no attribution at all.
  @group_a ~w(notification orderUpdates userEvents)

  # Fields that can be demultiplexed from an inbound frame, per channel.
  # Anything not listed here is part of the identity but not of the routing key.
  @demux %{
    "activeAssetCtx" => [:coin],
    "activeSpotAssetCtx" => [:coin],
    "activeAssetData" => [:user, :coin],
    "allDexsClearinghouseState" => [:user],
    "allMids" => [:dex],
    "assetCtxs" => [:dex],
    "bbo" => [:coin],
    "candle" => [:coin, :interval],
    "clearinghouseState" => [:user, :dex],
    "l2Book" => [:coin],
    "openOrders" => [:user, :dex],
    "spotState" => [:user],
    "trades" => [:coin],
    "twapStates" => [:user, :dex],
    "userFills" => [:user],
    "userFundings" => [:user],
    "userHistoricalOrders" => [:user],
    "userNonFundingLedgerUpdates" => [:user],
    "userTwapHistory" => [:user],
    "userTwapSliceFills" => [:user],
    "webData2" => [:user],
    "webData3" => [:user]
  }

  @doc "Channels whose events carry no attribution (max one such user per connection)."
  @spec group_a_channels() :: [String.t()]
  def group_a_channels, do: @group_a

  @doc "True when `channel` has no attribution in its events."
  @spec group_a?(String.t() | t()) :: boolean()
  def group_a?(%__MODULE__{channel: channel}), do: group_a?(channel)
  def group_a?(channel) when is_binary(channel), do: channel in @group_a

  @doc "The `request_type` (WS channel) declared by a subscription module."
  @spec request_type(module()) :: String.t()
  def request_type(module) do
    Code.ensure_loaded(module)

    if function_exported?(module, :__subscription_info__, 0) do
      module.__subscription_info__().request_type
    else
      module |> Module.split() |> List.last() |> Macro.underscore()
    end
  end

  @doc "The `key_fields` declared by a subscription module (may be empty)."
  @spec key_fields(module()) :: [atom()]
  def key_fields(module) do
    Code.ensure_loaded(module)

    if function_exported?(module, :__subscription_info__, 0) do
      module.__subscription_info__()[:key_fields] || []
    else
      []
    end
  end

  @doc """
  Build the full canonical identity of a subscription.

  Includes every declared key field, even ones the server never echoes, so
  `l2Book BTC nSigFigs=5` and `l2Book BTC` are distinct subscriptions.
  """
  @spec identity(module(), map()) :: t()
  def identity(module, params) do
    channel = request_type(module)

    fields =
      module
      |> key_fields()
      |> Enum.reduce(%{}, fn field, acc ->
        case fetch_param(params, field) do
          nil -> acc
          value -> Map.put(acc, field, normalize(field, value))
        end
      end)

    %__MODULE__{module: module, channel: channel, fields: fields}
  end

  @doc """
  Build the routing key of a subscription: the identity restricted to fields
  the server actually echoes back in event frames.
  """
  @spec routing_key(module(), map()) :: t()
  def routing_key(module, params) do
    module |> identity(params) |> to_routing_key()
  end

  @doc "Restrict an identity to its demultiplexable fields."
  @spec to_routing_key(t()) :: t()
  def to_routing_key(%__MODULE__{channel: channel, fields: fields} = key) do
    demuxable = Map.get(@demux, channel, [])
    %{key | fields: Map.take(fields, demuxable)}
  end

  @doc "The user address a subscription is scoped to, or `nil`."
  @spec user(t()) :: String.t() | nil
  def user(%__MODULE__{fields: fields}), do: Map.get(fields, :user)

  @doc "Stable string form, usable as an ETS/Registry key."
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{channel: channel, fields: fields}) do
    parts =
      fields
      |> Enum.sort_by(fn {k, _} -> Atom.to_string(k) end)
      |> Enum.map_join(",", fn {k, v} -> "#{k}=#{v}" end)

    if parts == "", do: channel, else: "#{channel}|#{parts}"
  end

  @doc """
  True when two identities refer to the same subscription.
  """
  @spec same?(t(), t()) :: boolean()
  def same?(%__MODULE__{} = a, %__MODULE__{} = b) do
    a.channel == b.channel and a.fields == b.fields
  end

  @doc """
  Should `message` be delivered to the subscription identified by `key`?

  Matches on channel first, then on every demultiplexable field the frame
  actually echoes. Fields the frame does not echo (e.g. `l2Book`'s `nSigFigs`)
  cannot be checked; the connection packer is responsible for never colocating
  two such ambiguous subscriptions.
  """
  @spec matches?(t(), map()) :: boolean()
  def matches?(%__MODULE__{} = key, message) when is_map(message) do
    case message["channel"] do
      nil ->
        false

      channel ->
        channel == key.channel and fields_match?(key, message["data"])
    end
  end

  def matches?(_key, _message), do: false

  @doc """
  Frame matching for raw subscription request maps (as used by
  `Hyperliquid.Transport.WebSocket`, which holds requests rather than modules).
  """
  @spec matches_request?(map(), map()) :: boolean()
  def matches_request?(request, message) when is_map(request) and is_map(message) do
    channel = fetch_param(request, :type)

    key = %__MODULE__{
      channel: to_string_value(channel),
      fields: request_fields(request, to_string_value(channel))
    }

    matches?(key, message)
  end

  defp request_fields(request, channel) do
    @demux
    |> Map.get(channel, [])
    |> Enum.reduce(%{}, fn field, acc ->
      case fetch_param(request, request_param_name(channel, field)) do
        nil -> acc
        value -> Map.put(acc, field, normalize(field, value))
      end
    end)
  end

  # `candle` takes `coin` + `interval` as request params but echoes `s` + `i`.
  defp request_param_name(_channel, field), do: field

  defp fields_match?(%__MODULE__{channel: channel, fields: fields}, data) do
    demuxable = Map.get(@demux, channel, [])

    Enum.all?(demuxable, fn field ->
      case {Map.get(fields, field), extract(field, data)} do
        {nil, _} -> true
        {_, nil} -> true
        {want, got} -> want == got
      end
    end)
  end

  # ===================== Field extraction from frames =====================

  defp extract(field, data) when is_list(data) do
    case data do
      [first | _] -> extract(field, first)
      [] -> nil
    end
  end

  defp extract(:coin, data) when is_map(data) do
    # `candle` echoes the symbol as "s"
    normalize_maybe(:coin, data["coin"] || data["s"])
  end

  defp extract(:interval, data) when is_map(data) do
    normalize_maybe(:interval, data["interval"] || data["i"])
  end

  defp extract(:user, data) when is_map(data) do
    user =
      data["user"] ||
        case data["userState"] do
          %{"user" => u} -> u
          _ -> nil
        end

    normalize_maybe(:user, user)
  end

  defp extract(:dex, data) when is_map(data) do
    normalize_maybe(:dex, data["dex"])
  end

  defp extract(_field, _data), do: nil

  defp normalize_maybe(_field, nil), do: nil
  defp normalize_maybe(field, value), do: normalize(field, value)

  defp normalize(:user, value), do: value |> to_string_value() |> String.downcase()
  defp normalize(:dex, ""), do: nil
  defp normalize(_field, value), do: to_string_value(value)

  defp to_string_value(value) when is_binary(value), do: value
  defp to_string_value(value), do: Kernel.to_string(value)

  defp fetch_param(params, field) when is_map(params) do
    Map.get(params, field) || Map.get(params, Atom.to_string(field))
  end

  defp fetch_param(_params, _field), do: nil
end
