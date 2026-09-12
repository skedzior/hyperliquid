defmodule Hyperliquid.Api.Subscription.TwapStates do
  @moduledoc """
  WebSocket subscription for TWAP execution states.

  ## TWAP state shape (untyped passthrough)

  Each entry is `%{"twapId" => id, "state" => state, "status" => status}` where
  `state` matches the `twapHistory` record state - including the fields added
  upstream in v0.33.3:

      %{"coin" => "BTC", "executedNtl" => "..", "executedSz" => "..",
        "minutes" => 30, "randomize" => false, "reduceOnly" => false,
        "side" => "B" | "A", "sz" => "..", "timestamp" => 1700000000000,
        "user" => "0x…",
        "stopPx" => "..." | nil,                       # termination price
        "trigger" => %{"px" => "...", "above" => true} | nil}

  and `status` is `%{"status" => s, "description" => ".."}` with `s` one of
  `"finished"`, `"activated"`, `"terminated"`, `"waitingForTrigger"`, `"stopped"`
  or `"error"` (the last two pairs are new in v0.33.3).

  WebSocket payloads are **not** snake_cased by this SDK, so the keys arrive
  camelCase exactly as above.

  `dex` is optional and defaults to `""` (the main dex), matching
  `@nktkas/hyperliquid` - the response always echoes the dex back.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/subscriptions
  """

  use Hyperliquid.Api.SubscriptionEndpoint,
    request_type: "twapStates",
    params: [:user],
    optional_params: [:dex],
    connection_type: :user_grouped,
    doc: "TWAP execution states - shares connection per user"

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:user, :string)
    field(:dex, :string)
    field(:states, {:array, :map})
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
         type: "twapStates",
         user: get_change(changeset, :user),
         dex: get_change(changeset, :dex) || ""
       }}
    else
      {:error, changeset}
    end
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event \\ %__MODULE__{}, attrs) do
    event
    |> cast(attrs, [:user, :dex, :states])
  end
end
