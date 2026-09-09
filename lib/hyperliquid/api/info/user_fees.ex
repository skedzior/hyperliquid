defmodule Hyperliquid.Api.Info.UserFees do
  @moduledoc """
  User's trading fee rates.

  Returns maker and taker fee rates for a user.

  ## `staking_link` is a discriminated union

  As of `@nktkas/hyperliquid` v0.33.3 the shape depends on `type`, and the two
  variants carry **different keys**:

      %{"type" => "requested",   "staking_user"  => "0x…"}
      %{"type" => "tradingUser", "staking_user"  => "0x…"}
      %{"type" => "stakingUser", "trading_user"  => "0x…"}   # note: trading_user!
      nil

  It used to always carry `stakingUser`, so any consumer reading
  `staking_link["staking_user"]` unconditionally breaks on the `"stakingUser"`
  variant. Use `staking_link_counterparty/1`.

  `next_trial_available_timestamp` widened upstream from `unknown | null` to
  `number | null` (ms since epoch) - already modelled as `:integer` here.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint#retrieve-a-users-fee-rates
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "userFees",
    params: [:user],
    rate_limit_cost: 1,
    doc: "Retrieve user's trading fee rates",
    returns: "Maker and taker fee rates"

  @type t :: %__MODULE__{
          daily_user_vlm: [map()],
          fee_schedule: map(),
          user_cross_rate: String.t(),
          user_add_rate: String.t(),
          user_spot_cross_rate: String.t(),
          user_spot_add_rate: String.t(),
          active_referral_discount: String.t(),
          trial: term(),
          fee_trial_escrow: String.t(),
          next_trial_available_timestamp: term(),
          staking_link: map() | nil,
          active_staking_discount: map()
        }

  @primary_key false
  embedded_schema do
    field(:daily_user_vlm, {:array, :map})
    field(:fee_schedule, :map)
    field(:user_cross_rate, :string)
    field(:user_add_rate, :string)
    field(:user_spot_cross_rate, :string)
    field(:user_spot_add_rate, :string)
    field(:active_referral_discount, :string)
    field(:trial, :map)
    field(:fee_trial_escrow, :string)
    field(:next_trial_available_timestamp, :integer)
    field(:staking_link, :map)
    field(:active_staking_discount, :map)
  end

  # ===================== Changesets =====================

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(fees \\ %__MODULE__{}, attrs) do
    fees
    |> cast(attrs, [
      :daily_user_vlm,
      :fee_schedule,
      :user_cross_rate,
      :user_add_rate,
      :user_spot_cross_rate,
      :user_spot_add_rate,
      :active_referral_discount,
      :trial,
      :fee_trial_escrow,
      :next_trial_available_timestamp,
      :staking_link,
      :active_staking_discount
    ])
    |> validate_required([:user_cross_rate, :user_add_rate])
  end

  # ===================== Helpers =====================

  @doc """
  Return `{type, counterparty_address}` from the `staking_link` union.

  Handles the key difference between the variants (`staking_user` vs
  `trading_user`). Returns `nil` when there is no staking link.

      iex> alias Hyperliquid.Api.Info.UserFees
      iex> UserFees.staking_link_counterparty(%UserFees{staking_link: %{"type" => "stakingUser", "trading_user" => "0xabc"}})
      {"stakingUser", "0xabc"}
  """
  @spec staking_link_counterparty(t()) :: {String.t(), String.t() | nil} | nil
  def staking_link_counterparty(%__MODULE__{staking_link: link}) when is_map(link) do
    type = link["type"] || link[:type]

    address =
      link["staking_user"] || link[:staking_user] || link["stakingUser"] ||
        link["trading_user"] || link[:trading_user] || link["tradingUser"]

    {type, address}
  end

  def staking_link_counterparty(_), do: nil

  @doc """
  Get cross rate as float.
  """
  @spec cross_rate_float(t()) :: {:ok, float()} | {:error, :parse_error}
  def cross_rate_float(%__MODULE__{user_cross_rate: rate}) do
    case Float.parse(rate) do
      {f, _} -> {:ok, f}
      :error -> {:error, :parse_error}
    end
  end

  @doc """
  Get add rate as float.
  """
  @spec add_rate_float(t()) :: {:ok, float()} | {:error, :parse_error}
  def add_rate_float(%__MODULE__{user_add_rate: rate}) do
    case Float.parse(rate) do
      {f, _} -> {:ok, f}
      :error -> {:error, :parse_error}
    end
  end
end
