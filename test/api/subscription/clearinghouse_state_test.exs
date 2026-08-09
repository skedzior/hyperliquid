defmodule Hyperliquid.Api.Subscription.ClearinghouseStateTest do
  use ExUnit.Case, async: true

  alias Hyperliquid.Api.Subscription.ClearinghouseState

  @user "0x1234567890123456789012345678901234567890"

  describe "build_request/1" do
    test "builds a request for the main perps market when dex is omitted" do
      assert {:ok, %{type: "clearinghouseState", user: @user, dex: ""}} =
               ClearinghouseState.build_request(%{user: @user})
    end

    test "builds a request for the main perps market when dex is the empty string" do
      # Regression: validate_required/2 treats "" as missing, so the documented
      # default for the main perps dex made the subscription unbuildable.
      assert {:ok, %{dex: ""}} =
               ClearinghouseState.build_request(%{user: @user, dex: ""})
    end

    test "builds a request for a named builder-deployed dex" do
      assert {:ok, %{dex: "test"}} =
               ClearinghouseState.build_request(%{user: @user, dex: "test"})
    end

    test "still requires a user" do
      assert {:error, changeset} = ClearinghouseState.build_request(%{dex: ""})
      assert {"can't be blank", [validation: :required]} = changeset.errors[:user]
    end

    test "still rejects a malformed user address" do
      assert {:error, changeset} = ClearinghouseState.build_request(%{user: "0xnope"})
      assert changeset.errors[:user]
    end
  end
end
