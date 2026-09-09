defmodule Hyperliquid.Api.Info do
  @moduledoc """
  Convenience functions for Info API endpoints.

  This module provides snake_case wrapper functions that delegate to the
  underlying endpoint modules, improving developer ergonomics.

  ## Usage

      # Direct endpoint call (still supported)
      {:ok, mids} = Hyperliquid.Api.Info.AllMids.request()

      # Convenience wrapper (new)
      {:ok, mids} = Hyperliquid.Api.Info.all_mids()

      # With parameters
      {:ok, book} = Hyperliquid.Api.Info.l2_book("BTC")
      {:ok, state} = Hyperliquid.Api.Info.clearinghouse_state("0xabc...")

  ## Available Functions

  All Info endpoints are available as snake_case functions. Each endpoint
  provides both safe and bang variants:

  - `endpoint_name(...)` - Returns `{:ok, result}` or `{:error, reason}`
  - `endpoint_name!(...)` - Returns `result` or raises on error

  For endpoints with storage enabled, additional `fetch_*` variants are available:

  - `fetch_endpoint_name(...)` - Request and persist to storage backends

  See `Hyperliquid.Api.Registry.list_by_type(:info)` for all available endpoints.

  ## Return-shape caveats

  `settled_outcome/1` and `vault_details/1` answer `{:ok, nil}` when the API
  returns `null` (an unsettled outcome, or a vault address that does not exist)
  rather than failing changeset validation.
  """

  # Generate delegated functions for all Info endpoints at compile time
  require Hyperliquid.Api.DelegationHelper
  Hyperliquid.Api.DelegationHelper.generate_delegated_functions(:info)
end
