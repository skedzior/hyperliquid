defmodule Hyperliquid.Api.Subscription.ClearinghouseStateTest do
  use ExUnit.Case, async: true

  alias Hyperliquid.Api.Subscription.ClearinghouseState

  test "builds a request for the main perps market when dex is omitted" do
    assert {:ok, %{type: "clearinghouseState", user: "0x" <> _, dex: ""}} =
             ClearinghouseState.build_request(%{user: "0x1234567890123456789012345678901234567890"})
  end

  test "builds a request for the main perps market when dex is the empty string" do
    assert {:ok, %{dex: ""}} =
             ClearinghouseState.build_request(%{
               user: "0x1234567890123456789012345678901234567890",
               dex: ""
             })
  end

  test "builds a request for a named builder-deployed dex" do
    assert {:ok, %{dex: "test"}} =
             ClearinghouseState.build_request(%{
               user: "0x1234567890123456789012345678901234567890",
               dex: "test"
             })
  end

  test "still requires a user" do
    assert {:error, changeset} = ClearinghouseState.build_request(%{dex: ""})
    assert {"can't be blank", [validation: :required]} = changeset.errors[:user]
  end
end
