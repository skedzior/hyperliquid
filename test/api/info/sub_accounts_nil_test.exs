defmodule Hyperliquid.Api.Info.SubAccountsNilTest do
  use ExUnit.Case, async: true

  alias Hyperliquid.Api.Info.{SubAccounts, SubAccounts2}

  # Observed live on mainnet 2026-09-09: a user with no sub-accounts gets `null`, not `[]`.
  test "subAccounts null response preprocesses to an empty account list" do
    assert SubAccounts.preprocess(nil) == %{accounts: []}
    assert SubAccounts2.preprocess(nil) == %{accounts: []}
  end

  test "subAccounts list response is wrapped" do
    assert SubAccounts.preprocess([]) == %{accounts: []}
  end
end
