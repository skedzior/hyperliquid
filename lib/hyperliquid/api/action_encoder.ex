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

  Both the signed preimage and the request body must be built from the value
  returned by `canonicalize/1`, otherwise the bytes that were hashed and the
  bytes that were sent can disagree.

  ## Where the field order lives

  This module is the encoding entry point; the field order itself is declared
  per action type in `Hyperliquid.Api.Exchange.Action`, transcribed from the
  `@nktkas/hyperliquid` valibot request schemas (the same orders the reference
  Python SDK's dict literals produce).

  It used to carry a single global key ranking of its own. That was replaced by
  the per-action-type schemas because a global ranking can only be correct while
  no key needs a different relative position in two different shapes — an
  assumption that holds for the trading path but has no reason to hold for every
  action Hyperliquid adds.
  """

  alias Hyperliquid.Api.Exchange.Action

  @doc """
  Rewrite an action into `Jason.OrderedObject` values in canonical field order.

  Idempotent: canonicalizing an already-canonical value returns it unchanged, so
  it is safe to pipe an action through this on the way to the wire even when the
  endpoint module has already ordered it.
  """
  @spec canonicalize(term()) :: term()
  defdelegate canonicalize(action), to: Action, as: :ordered

  @doc """
  Canonicalize and JSON-encode an action.

  Returns `{:ok, json}` or `{:error, reason}` from `Jason.encode/1`.
  """
  @spec encode(term()) :: {:ok, String.t()} | {:error, term()}
  def encode(action), do: action |> canonicalize() |> Jason.encode()
end
