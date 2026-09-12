defmodule Hyperliquid.Api.Subscription.SubscriptionGapsTest do
  @moduledoc """
  Subscription-request shapes and event casting for the WS gaps closed against
  `@nktkas/hyperliquid` v0.33.3 and the official subscriptions page. No network.
  """
  use ExUnit.Case, async: true

  alias Hyperliquid.Api.Subscription.{
    ClearinghouseState,
    OpenOrders,
    OutcomeMetaUpdates,
    TwapStates,
    UserFills,
    WebData2,
    WebData3
  }

  @user "0x" <> String.duplicate("1", 40)

  describe "optional dex param (docs C4)" do
    for {mod, type} <- [
          {ClearinghouseState, "clearinghouseState"},
          {OpenOrders, "openOrders"},
          {TwapStates, "twapStates"}
        ] do
      test "#{type} defaults dex to the main dex" do
        assert {:ok, request} = unquote(mod).build_request(%{user: @user})
        assert request == %{type: unquote(type), user: @user, dex: ""}
      end

      test "#{type} passes an explicit dex through" do
        assert {:ok, request} = unquote(mod).build_request(%{user: @user, dex: "test"})
        assert request.dex == "test"
      end

      test "#{type} declares dex as optional" do
        info = unquote(mod).__subscription_info__()
        assert info.params == [:user]
        assert info.optional_params == [:dex]
      end

      test "#{type} still requires the user" do
        assert {:error, %Ecto.Changeset{}} = unquote(mod).build_request(%{})
      end
    end
  end

  describe "userFills subscription widened fill shape" do
    test "casts builderFee/feeTrialEscrow/twapId/cloid/liquidation from camelCase WS keys" do
      event = %{
        "fills" => [
          %{
            "coin" => "BTC",
            "px" => "50000.0",
            "sz" => "0.1",
            "side" => "B",
            "time" => 1_700_000_000_000,
            "startPosition" => "0.0",
            "dir" => "Open Long",
            "closedPnl" => "0.0",
            "hash" => "0x" <> String.duplicate("a", 64),
            "oid" => 1,
            "crossed" => true,
            "fee" => "1.0",
            "builderFee" => "0.1",
            "tid" => 2,
            "feeToken" => "USDC",
            "feeTrialEscrow" => "0.5",
            "twapId" => 42,
            "cloid" => "0x" <> String.duplicate("b", 32),
            "liquidation" => %{"markPx" => "49000.0", "method" => "backstop"}
          }
        ]
      }

      assert %Ecto.Changeset{valid?: true} = cs = UserFills.changeset(event)
      assert [fill] = Ecto.Changeset.apply_changes(cs).fills

      assert fill.builder_fee == "0.1"
      assert fill.fee_trial_escrow == "0.5"
      assert fill.twap_id == 42
      assert fill.cloid == "0x" <> String.duplicate("b", 32)
      assert fill.liquidation.mark_px == "49000.0"
      assert fill.liquidation.method == "backstop"
      assert fill.liquidation.liquidated_user == nil
    end
  end

  describe "webData3 abstraction (official docs)" do
    test "casts the account abstraction mode on user_state" do
      event = %{
        "userState" => %{
          "cumLedger" => "0.0",
          "serverTime" => 1_700_000_000_000,
          "isVault" => false,
          "user" => @user,
          "abstraction" => "unifiedAccount",
          "dexAbstractionEnabled" => true
        },
        "perpDexStates" => [
          %{"totalVaultEquity" => "0.0", "assetCtxs" => []}
        ]
      }

      assert {:ok, parsed} = WebData3.parse_event(event)
      assert parsed.user_state.abstraction == "unifiedAccount"
      assert WebData3.abstraction(parsed) == "unifiedAccount"
      assert WebData3.dex_abstraction_enabled?(parsed)
    end

    test "abstraction is absent on default-mode accounts" do
      event = %{
        "userState" => %{
          "cumLedger" => "0.0",
          "serverTime" => 1,
          "isVault" => false,
          "user" => @user
        },
        "perpDexStates" => [%{"totalVaultEquity" => "0.0", "assetCtxs" => []}]
      }

      assert {:ok, parsed} = WebData3.parse_event(event)
      assert WebData3.abstraction(parsed) == nil
    end
  end

  describe "webData2 channel deprecation (nktkas §D)" do
    test "the module is retained, not deleted" do
      assert Code.ensure_loaded?(WebData2)
      assert WebData2.__subscription_info__().request_type == "webData2"
    end

    test "the moduledoc warns that the channel was removed upstream" do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(WebData2)
      assert doc =~ "Deprecated"
      assert doc =~ "removed upstream"
      assert doc =~ "WebData3"
    end

    test "the info webData2 method is NOT deprecated" do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(Hyperliquid.Api.Info.WebData2)
      refute doc =~ "Deprecated"
    end
  end
end
