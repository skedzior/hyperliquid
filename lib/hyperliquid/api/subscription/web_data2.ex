defmodule Hyperliquid.Api.Subscription.WebData2 do
  @moduledoc """
  WebSocket subscription for comprehensive user and market data.

  Auto-generated from @nktkas/hyperliquid v0.26.0
  Source: src/api/subscription/webData2.ts

  ## Description

  Subscription to comprehensive user and market data events. This includes:
  - Clearinghouse state (perpetual trading account summary)
  - Leading vaults information
  - Open orders with frontend information
  - Agent information
  - Market metadata and asset contexts
  - TWAP states
  - Spot state and asset contexts (optional)

  ## Usage

      # Subscribe to webData2 events
      params = %{user: "0x..."}
      Hyperliquid.Api.Subscription.WebData2.subscribe(params, fn event ->
        IO.inspect(event, label: "WebData2 Event")
      end)
  """
  use Hyperliquid.Api.SubscriptionEndpoint,
    request_type: "webData2",
    params: [:user],
    connection_type: :user_grouped,
    doc: "Comprehensive user and market data - shares connection per user",
    storage: [
      postgres: [
        enabled: true,
        table: "user_snapshots",
        # Only save user-specific state, not market data (asset_ctxs, meta, etc.)
        fields: [
          :user,
          :clearinghouse_state,
          :open_orders,
          :spot_state,
          :twap_states,
          :server_time
        ]
      ],
      cache: [
        enabled: true,
        key_pattern: "webdata2:{{user}}",
        # Cache the same user-specific fields for quick access
        fields: [
          :user,
          :clearinghouse_state,
          :open_orders,
          :spot_state,
          :twap_states,
          :server_time
        ]
      ]
    ]

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
      {:ok, %{type: "webData2", user: get_change(changeset, :user)}}
    else
      {:error, changeset}
    end
  end

  # ===================== Event Schema =====================

  @primary_key false
  embedded_schema do
    # Clearinghouse state
    embeds_one :clearinghouse_state, ClearinghouseState do
      field(:margin_summary, :map)
      field(:cross_margin_summary, :map)
      field(:withdrawable, :string)
      field(:asset_positions, {:array, :map})
      # Additional fields from ClearinghouseStateResponse
    end

    # Leading vaults
    embeds_many :leading_vaults, LeadingVault do
      field(:address, :string)
      field(:name, :string)
    end

    field(:total_vault_equity, :string)

    # Open orders
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

    field(:agent_address, :string)
    field(:agent_valid_until, :integer)
    field(:cum_ledger, :string)

    # Meta - perpetual metadata
    field(:meta, :map)

    # Asset contexts - perpetual
    field(:asset_ctxs, {:array, :map})

    field(:server_time, :integer)
    field(:is_vault, :boolean)
    field(:user, :string)

    # TWAP states - array of [id, state] tuples
    embeds_many :twap_states, TwapState do
      field(:twap_id, :integer)
      field(:coin, :string)
      field(:executed_ntl, :string)
      field(:executed_sz, :string)
      field(:minutes, :integer)
      field(:randomize, :boolean)
      field(:reduce_only, :boolean)
      field(:side, :string)
      field(:sz, :string)
      field(:timestamp, :integer)
      field(:user, :string)
    end

    # Spot state (optional)
    embeds_one :spot_state, SpotState do
      field(:balances, {:array, :map})
    end

    # Spot asset contexts
    field(:spot_asset_ctxs, {:array, :map})

    # Optional fields
    field(:opt_out_of_spot_dusting, :boolean, default: false)
    field(:perps_at_open_interest_cap, {:array, :string})
  end

  @doc """
  Changeset for validating webData2 event data.
  """
  def changeset(event \\ %__MODULE__{}, attrs) do
    event
    |> cast(attrs, [
      :total_vault_equity,
      :agent_address,
      :agent_valid_until,
      :cum_ledger,
      :meta,
      :asset_ctxs,
      :server_time,
      :is_vault,
      :user,
      :spot_asset_ctxs,
      :opt_out_of_spot_dusting,
      :perps_at_open_interest_cap
    ])
    |> cast_embed(:clearinghouse_state)
    |> cast_embed(:leading_vaults)
    |> cast_embed(:open_orders)
    |> cast_embed(:twap_states)
    |> cast_embed(:spot_state)
    |> validate_required([
      :total_vault_equity,
      :cum_ledger,
      :server_time,
      :is_vault,
      :user
    ])
    |> validate_format(:user, ~r/^0x[0-9a-fA-F]{40}$/)
  end

  @doc """
  Parses raw WebSocket event data into structured format.
  """
  def parse_event(data) when is_map(data) do
    # Transform the data to match our schema
    transformed =
      data
      |> snake_case_keys()
      |> transform_twap_states()

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
    |> Enum.map(fn {k, v} -> {to_snake_case(k), v} end)
    |> Enum.into(%{})
  end

  defp to_snake_case(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> to_snake_case()
    |> String.to_atom()
  end

  # Single-character keys have no word boundary to split on. Macro.underscore/1
  # downcases them ("T" -> "t"), which would collapse distinct sibling keys into
  # one and silently drop a field. Pass them through unchanged.
  defp to_snake_case(<<_::utf8>> = key), do: key

  defp to_snake_case(key) when is_binary(key) do
    key
    |> Macro.underscore()
  end

  # Transform TWAP states from [[id, state], ...] to embedded schema format
  defp transform_twap_states(%{twap_states: twap_list} = data) when is_list(twap_list) do
    transformed_twaps =
      Enum.map(twap_list, fn
        [twap_id, state] when is_map(state) ->
          state
          |> snake_case_keys()
          |> Map.put(:twap_id, twap_id)

        other ->
          other
      end)

    Map.put(data, :twap_states, transformed_twaps)
  end

  defp transform_twap_states(data), do: data

  # ===================== Subscription Functions =====================

  @doc """
  Subscribe to webData2 events for a specific user.

  ## Parameters

  - `params`: Map with `:user` key (Ethereum address)
  - `callback`: Function to handle incoming events

  ## Returns

  - `{:ok, subscription}` - Subscription handle
  - `{:error, reason}` - If subscription fails

  ## Example

      WebData2.subscribe(
        %{user: "0x1234..."},
        fn event ->
          IO.puts("Vault equity: \#{event.total_vault_equity}")
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
end
