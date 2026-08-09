defmodule Hyperliquid.Api.ActionEncoder do
  @moduledoc """
  Canonical JSON encoding for exchange actions.

  Hyperliquid derives an L1 action's connection id from the *msgpack* encoding of
  the action. msgpack preserves field order, so the resulting hash depends on the
  order in which fields are serialized.

  Elixir maps do not preserve insertion order. Keys are stored in term order, and
  for atom keys that order follows the atom table, which is populated in a
  different sequence on every BEAM run. Encoding an action directly from a map
  therefore produced a *different connection id on each boot*:

      0x4dfe89e6ccf2066c47f5a9a935d4c0c82697b240071f83b9593a4b4db11bb7dc
      0x5a9622bad83165511b1bfda92b4274f841547cbad8dc47bac0bcf4b29dd5f17a
      0x716ee448bc143896bfad2dcda1baec8984550e6276caabb4c5e48ec11975fb28

  This module renders an action into `Jason.OrderedObject` values using the field
  order fixed by the reference implementations, so the signed preimage is stable
  across runs and matches what the exchange computes.

  Both the signed preimage and the request body must be built from the value
  returned by `canonicalize/1`, otherwise the bytes that were hashed and the
  bytes that were sent can disagree.

  ## Field order

  `@field_order` is a single global ranking applied at every level of the action.
  A key that does not appear in it sorts after every known key, lexicographically,
  so unrecognized actions still encode deterministically even when their canonical
  order is unknown.

  The trading-path ranking is taken from the reference Python SDK
  (`hyperliquid/utils/signing.py` — `order_wires_to_order_action/3`,
  `order_request_to_order_wire/2`, `order_type_to_wire/1`) and verified against it
  by `test/api/action_encoder_test.exs`.

  Keys for the newer actions (HIP-4 outcomes, gossip priority, agent asset
  transfers) are ordered to match the field order declared by the nktkas
  TypeScript SDK's request schemas, which is the order its own `canonicalize`
  emits. Those have no published reference hashes to check against, so unlike the
  trading path they are not verified end to end — they are as good as that
  schema.
  """

  # Ordered by rank. Keys absent from this list sort last, lexicographically.
  #
  # No key needs a different relative position in two different shapes, which is
  # what lets a single global ranking work; action_encoder_test.exs asserts this
  # for every shape covered here.
  @field_order ~w(
    type
    orders grouping builder
    cancels modifies
    oid order
    asset isCross leverage isBuy ntli
    time
    a b p s r t c f o cloid
    limit trigger
    tif
    isMarket triggerPx tpsl
    activate deactivate venueName
    splitOutcome mergeOutcome mergeQuestion negateOutcome
    question outcome
    destination sourceDex destinationDex token role input create
    dex ntl isDeposit
    slotId ip maxGas
    amount fromSubAccount nonce
  )

  @ranks @field_order |> Enum.with_index() |> Map.new()
  @unranked length(@field_order)

  @doc """
  Recursively rewrite an action so that every map becomes an order-preserving
  `Jason.OrderedObject` in canonical field order.

  Lists are walked element-wise. Scalars are returned unchanged.
  """
  @spec canonicalize(term()) :: term()
  def canonicalize(%Jason.OrderedObject{values: values}) do
    %Jason.OrderedObject{values: Enum.map(values, fn {k, v} -> {k, canonicalize(v)} end)}
  end

  def canonicalize(%_struct{} = value), do: value

  def canonicalize(map) when is_map(map) do
    values =
      map
      |> Enum.map(fn {k, v} -> {to_key(k), canonicalize(v)} end)
      |> Enum.sort_by(fn {k, _v} -> {rank(k), k} end)

    %Jason.OrderedObject{values: values}
  end

  def canonicalize(list) when is_list(list), do: Enum.map(list, &canonicalize/1)

  def canonicalize(value), do: value

  @doc """
  Encode an action as canonical JSON.

  Returns the same `{:ok, iodata}` / `{:error, reason}` shape as `Jason.encode/1`.
  """
  @spec encode(term()) :: {:ok, String.t()} | {:error, Exception.t()}
  def encode(action), do: action |> canonicalize() |> Jason.encode()

  @doc """
  The canonical field ranking, most significant first. Exposed for tests.
  """
  @spec field_order() :: [String.t()]
  def field_order, do: @field_order

  defp to_key(k) when is_atom(k), do: Atom.to_string(k)
  defp to_key(k) when is_binary(k), do: k

  defp rank(key), do: Map.get(@ranks, key, @unranked)
end
