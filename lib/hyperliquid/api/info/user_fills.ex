defmodule Hyperliquid.Api.Info.UserFills do
  @moduledoc """
  User's trade fills.

  Returns list of executed trades for a user.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint#retrieve-a-users-fills

  ## Usage

      {:ok, fills} = UserFills.request("0x...")
      {:ok, pnl} = UserFills.total_pnl(fills)
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "userFills",
    params: [:user],
    optional_params: [:aggregateByTime],
    rate_limit_cost: 20,
    doc: "Retrieve a user's trade fills",
    returns: "UserFills struct with list of executed trades",
    storage: [
      postgres: [
        enabled: true,
        table: "fills",
        extract: :fills
      ],
      cache: [
        enabled: true,
        ttl: :timer.minutes(1),
        key_pattern: "user_fills:{{user}}"
      ]
    ]

  @type t :: %__MODULE__{
          fills: [Fill.t()]
        }

  @primary_key false
  embedded_schema do
    embeds_many :fills, Fill, primary_key: false do
      field(:coin, :string)
      field(:px, :string)
      field(:sz, :string)
      field(:side, :string)
      field(:time, :integer)
      field(:start_position, :string)
      field(:dir, :string)
      field(:closed_pnl, :string)
      field(:hash, :string)
      field(:oid, :integer)
      field(:crossed, :boolean)
      field(:fee, :string)
      # Optional fee charged by the UI builder (negative = rebate)
      field(:builder_fee, :string)
      field(:tid, :integer)
      field(:fee_token, :string)
      # Fee trial escrow amount (optional; added upstream in v0.33.3)
      field(:fee_trial_escrow, :string)
      # ID of the parent TWAP, or nil for a non-TWAP fill
      field(:twap_id, :integer)
      # Client order id, when the order carried one
      field(:cloid, :string)

      # Liquidation details, present only on liquidation fills:
      #   %{liquidated_user: "0x…" | nil, mark_px: "…", method: "market" | "backstop"}
      # `liquidated_user` became OPTIONAL upstream in v0.33.3.
      embeds_one :liquidation, Liquidation, primary_key: false do
        @moduledoc "Liquidation details for a fill."

        field(:liquidated_user, :string)
        field(:mark_px, :string)
        field(:method, :string)
      end
    end
  end

  # ===================== Preprocessing =====================

  @doc false
  def preprocess(data) when is_list(data), do: %{fills: data}
  def preprocess(data), do: data

  # ===================== Changeset =====================

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(fills \\ %__MODULE__{}, attrs) do
    fills
    |> cast(attrs, [])
    |> cast_embed(:fills, with: &fill_changeset/2)
  end

  defp fill_changeset(fill, attrs) do
    attrs = normalize_attrs(attrs)

    fill
    |> cast(attrs, [
      :coin,
      :px,
      :sz,
      :side,
      :time,
      :start_position,
      :dir,
      :closed_pnl,
      :hash,
      :oid,
      :crossed,
      :fee,
      :builder_fee,
      :tid,
      :fee_token,
      :fee_trial_escrow,
      :twap_id,
      :cloid
    ])
    |> cast_embed(:liquidation, with: &liquidation_changeset/2)
    |> validate_required([:coin, :px, :sz, :side, :time])
  end

  defp liquidation_changeset(liquidation, attrs) do
    liquidation
    |> cast(attrs, [:liquidated_user, :mark_px, :method])
    |> validate_required([:mark_px, :method])
  end

  defp normalize_attrs(attrs) do
    %{
      coin: fetch_attr(attrs, "coin", "coin"),
      px: fetch_attr(attrs, "px", "px"),
      sz: fetch_attr(attrs, "sz", "sz"),
      side: fetch_attr(attrs, "side", "side"),
      time: fetch_attr(attrs, "time", "time"),
      start_position: fetch_attr(attrs, "startPosition", "start_position"),
      dir: fetch_attr(attrs, "dir", "dir"),
      closed_pnl: fetch_attr(attrs, "closedPnl", "closed_pnl"),
      hash: fetch_attr(attrs, "hash", "hash"),
      oid: fetch_attr(attrs, "oid", "oid"),
      crossed: fetch_attr(attrs, "crossed", "crossed"),
      fee: fetch_attr(attrs, "fee", "fee"),
      builder_fee: fetch_attr(attrs, "builderFee", "builder_fee"),
      tid: fetch_attr(attrs, "tid", "tid"),
      fee_token: fetch_attr(attrs, "feeToken", "fee_token"),
      fee_trial_escrow: fetch_attr(attrs, "feeTrialEscrow", "fee_trial_escrow"),
      twap_id: fetch_attr(attrs, "twapId", "twap_id"),
      cloid: fetch_attr(attrs, "cloid", "cloid"),
      liquidation: fetch_attr(attrs, "liquidation", "liquidation")
    }
  end

  # Fills reach this module either from the HTTP transport (keys already
  # snake_cased) or from a caller passing raw camelCase / atom keys, so try all
  # three spellings.
  defp fetch_attr(attrs, camel, snake) do
    Map.get(attrs, camel) || Map.get(attrs, snake) || Map.get(attrs, String.to_atom(snake))
  end

  @spec by_coin(t(), String.t()) :: [map()]
  def by_coin(%__MODULE__{fills: fills}, coin), do: Enum.filter(fills, &(&1.coin == coin))

  @spec total_pnl(t()) :: {:ok, float()} | {:error, :parse_error}
  def total_pnl(%__MODULE__{fills: fills}) do
    try do
      total = fills |> Enum.map(&String.to_float(&1.closed_pnl)) |> Enum.sum()
      {:ok, total}
    rescue
      _ -> {:error, :parse_error}
    end
  end
end
