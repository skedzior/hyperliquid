defmodule Hyperliquid.Api.Subscription.WebData3 do
  @moduledoc """
  WebSocket subscription for comprehensive user and market data (v3 format).

  Auto-generated from @nktkas/hyperliquid v0.26.0
  Source: src/api/subscription/webData3.ts

  ## Description

  Subscription to comprehensive user and market data events with support for multiple
  perpetual DEXes (HIP-3). This is the newer format that separates user state from
  per-DEX states.

  ## Key Differences from WebData2

  - User state is separated into its own object
  - Supports multiple perpetual DEX states (for HIP-3 DEX abstraction)
  - More structured data organization
  - Includes DEX abstraction flag (`dex_abstraction_enabled`) *and* the account
    abstraction mode (`abstraction`)

  ## Usage

      # Subscribe to webData3 events
      params = %{user: "0x..."}
      Hyperliquid.Api.Subscription.WebData3.subscribe(params, fn event ->
        IO.inspect(event.user_state, label: "User State")
        IO.inspect(event.perp_dex_states, label: "DEX States")
      end)
  """
  use Hyperliquid.Api.SubscriptionEndpoint,
    request_type: "webData3",
    params: [:user],
    connection_type: :user_grouped,
    doc: "Comprehensive user and market data (v3) - shares connection per user"

  @spec build_request(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def build_request(params) do
    types = %{user: :string}

    changeset =
      {%{}, types}
      |> cast(params, Map.keys(types))
      |> validate_required([:user])
      |> validate_format(:user, ~r/^0x[0-9a-fA-F]{40}$/,
        message: "must be a valid Ethereum address"
      )

    if changeset.valid? do
      {:ok, %{type: "webData3", user: get_change(changeset, :user)}}
    else
      {:error, changeset}
    end
  end

  # ===================== Event Schema =====================

  @primary_key false
  embedded_schema do
    # User state (shared across all DEXes)
    embeds_one :user_state, UserState do
      field(:agent_address, :string)
      field(:agent_valid_until, :integer)
      field(:cum_ledger, :string)
      field(:server_time, :integer)
      field(:is_vault, :boolean)
      field(:user, :string)
      field(:opt_out_of_spot_dusting, :boolean, default: false)
      field(:dex_abstraction_enabled, :boolean, default: false)

      # Account abstraction mode: "unifiedAccount" | "portfolioMargin" | "disabled".
      # Absent from the payload when the account is on the default mode.
      # The former "dexAbstraction" value was removed upstream in v0.33.3 - DEX
      # abstraction is now the separate `dex_abstraction_enabled` boolean above.
      field(:abstraction, :string)
    end

    # Per-DEX states (array to support multiple DEXes)
    embeds_many :perp_dex_states, PerpDexState do
      # Clearinghouse state for this DEX
      embeds_one :clearinghouse_state, ClearinghouseState do
        field(:margin_summary, :map)
        field(:cross_margin_summary, :map)
        field(:withdrawable, :string)
        field(:asset_positions, {:array, :map})
      end

      field(:total_vault_equity, :string)

      # Open orders for this DEX
      embeds_many :open_orders, DetailedOrder do
        field(:coin, :string)
        field(:side, :string)
        field(:limit_px, :string)
        field(:sz, :string)
        field(:oid, :integer)
        field(:timestamp, :integer)
        field(:orig_sz, :string)
        field(:trigger_condition, :string)
        field(:is_trigger, :boolean)
        field(:trigger_px, :string)
        field(:is_position_tpsl, :boolean)
        field(:reduce_only, :boolean)
        field(:order_type, :string)
        field(:cloid, :string)
      end

      # Asset contexts for this DEX
      field(:asset_ctxs, {:array, :map})

      # Assets at open interest cap
      field(:perps_at_open_interest_cap, {:array, :string})

      # Leading vaults for this DEX
      embeds_many :leading_vaults, LeadingVault do
        field(:address, :string)
        field(:name, :string)
      end
    end
  end

  @doc """
  Changeset for validating webData3 event data.
  """
  def changeset(event \\ %__MODULE__{}, attrs) do
    event
    |> cast(attrs, [])
    |> cast_embed(:user_state, required: true, with: &user_state_changeset/2)
    |> cast_embed(:perp_dex_states, required: true, with: &perp_dex_state_changeset/2)
  end

  # Changeset for UserState embedded schema
  defp user_state_changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :agent_address,
      :agent_valid_until,
      :cum_ledger,
      :server_time,
      :is_vault,
      :user,
      :opt_out_of_spot_dusting,
      :dex_abstraction_enabled,
      :abstraction
    ])
    |> validate_required([:cum_ledger, :server_time, :is_vault, :user])
    |> validate_format(:user, ~r/^0x[0-9a-fA-F]{40}$/)
  end

  # Changeset for PerpDexState embedded schema
  defp perp_dex_state_changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :total_vault_equity,
      :asset_ctxs,
      :perps_at_open_interest_cap
    ])
    |> cast_embed(:clearinghouse_state)
    |> cast_embed(:open_orders)
    |> cast_embed(:leading_vaults)
    |> validate_required([:total_vault_equity, :asset_ctxs])
  end

  @doc """
  Parses raw WebSocket event data into structured format.
  """
  def parse_event(data) when is_map(data) do
    transformed =
      data
      |> snake_case_keys()

    case changeset(%__MODULE__{}, transformed) do
      %Ecto.Changeset{valid?: true} = cs ->
        {:ok, apply_changes(cs)}

      %Ecto.Changeset{valid?: false} = cs ->
        {:error, {:validation_error, cs}}
    end
  end

  # ===================== Helper Functions =====================

  defp snake_case_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      {to_snake_case(k), maybe_snake_case_keys(v)}
    end)
    |> Enum.into(%{})
  end

  defp maybe_snake_case_keys(map) when is_map(map), do: snake_case_keys(map)

  defp maybe_snake_case_keys(list) when is_list(list),
    do: Enum.map(list, &maybe_snake_case_keys/1)

  defp maybe_snake_case_keys(value), do: value

  # `String.to_existing_atom/1`, never `String.to_atom/1`: keys can originate in
  # server frames and the atom table is never garbage collected.
  defp to_snake_case(key) when is_atom(key) do
    snake = key |> Atom.to_string() |> to_snake_case()

    try do
      String.to_existing_atom(snake)
    rescue
      ArgumentError -> snake
    end
  end

  # Single-character keys have no word boundary to split on. Macro.underscore/1
  # downcases them ("T" -> "t"), which would collapse distinct sibling keys into
  # one and silently drop a field. Pass them through unchanged.
  defp to_snake_case(<<_::utf8>> = key), do: key

  defp to_snake_case(key) when is_binary(key) do
    key
    |> Macro.underscore()
  end

  # ===================== Subscription Functions =====================

  @doc """
  Subscribe to webData3 events for a specific user.

  ## Parameters

  - `params`: Map with `:user` key (Ethereum address)
  - `callback`: Function to handle incoming events

  ## Returns

  - `{:ok, subscription}` - Subscription handle
  - `{:error, reason}` - If subscription fails

  ## Example

      WebData3.subscribe(
        %{user: "0x1234..."},
        fn event ->
          IO.inspect(event.user_state.is_vault, label: "Is Vault")

          Enum.each(event.perp_dex_states, fn dex_state ->
            IO.puts("Vault equity: \#{dex_state.total_vault_equity}")
          end)
        end
      )
  """
  def subscribe(params, callback) when is_function(callback, 1) do
    with {:ok, request} <- build_request(params) do
      # This would integrate with your WebSocket transport layer
      # Hyperliquid.WS.Stream.subscribe(request, &handle_event(&1, callback))
      {:ok, request}
    end
  end

  # ===================== Access Helpers =====================

  @doc """
  Get the main DEX state (first in the array, usually the primary DEX).
  """
  def main_dex_state(%__MODULE__{perp_dex_states: [main | _]}), do: main
  def main_dex_state(%__MODULE__{perp_dex_states: []}), do: nil

  @doc """
  Account abstraction mode: `"unifiedAccount"`, `"portfolioMargin"`, `"disabled"`,
  or `nil` when the account is on the default mode.
  """
  def abstraction(%__MODULE__{user_state: %{abstraction: abstraction}}), do: abstraction
  def abstraction(_), do: nil

  @doc """
  Check if DEX abstraction is enabled for this user.
  """
  def dex_abstraction_enabled?(%__MODULE__{user_state: %{dex_abstraction_enabled: enabled}}),
    do: enabled == true

  def dex_abstraction_enabled?(_), do: false

  @doc """
  Get total vault equity across all DEXes.
  """
  def total_vault_equity(%__MODULE__{perp_dex_states: dex_states}) do
    dex_states
    |> Enum.map(& &1.total_vault_equity)
    |> Enum.map(&parse_decimal/1)
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
    |> Decimal.to_string()
  end

  defp parse_decimal(str) when is_binary(str) do
    case Decimal.parse(str) do
      {decimal, _} -> decimal
      :error -> Decimal.new(0)
    end
  end
end
