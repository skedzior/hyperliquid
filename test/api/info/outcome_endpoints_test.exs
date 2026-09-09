defmodule Hyperliquid.Api.Info.OutcomeEndpointsTest do
  # The per-endpoint parsing tests for usdcRouting, outcomeTemplates, outcomeMeta,
  # settledOutcome, perpConciseAnnotations and gossipPriorityAuctionStatus were
  # dropped in the 2026-09 upstream sync: those modules already ship upstream and
  # are covered by test/api/outcome_markets_test.exs and
  # test/api/priority_and_routing_test.exs.
  @moduledoc """
  Request-shape and schema-casting tests for the info endpoints added from
  `@nktkas/hyperliquid` v0.33.3 and the official HIP-4 docs.

  All fixtures are literals taken from the upstream TypeScript types; nothing
  here hits the network.
  """
  use ExUnit.Case, async: true

  alias Hyperliquid.Api.Info.{
    GossipPriorityAuctionStatus,
    OutcomeDeployerLimits,
    OutcomeMeta,
    OutcomeTemplates,
    PerpConciseAnnotations,
    SettledOutcome,
    UsdcRouting
  }

  describe "request shapes" do
    test "no-param endpoints emit only a type" do
      assert UsdcRouting.build_request() == %{type: "usdcRouting"}
      assert OutcomeTemplates.build_request() == %{type: "outcomeTemplates"}
      assert OutcomeMeta.build_request() == %{type: "outcomeMeta"}
      assert PerpConciseAnnotations.build_request() == %{type: "perpConciseAnnotations"}

      assert GossipPriorityAuctionStatus.build_request() == %{
               type: "gossipPriorityAuctionStatus"
             }
    end

    test "settledOutcome carries the outcome id" do
      assert SettledOutcome.build_request(95) == %{type: "settledOutcome", outcome: 95}
    end

    test "outcomeDeployerLimits carries the venue" do
      assert OutcomeDeployerLimits.build_request("abc") == %{
               type: "outcomeDeployerLimits",
               venue: "abc"
             }
    end

    test "venue format helper matches the documented 2-4 lowercase letters" do
      assert OutcomeDeployerLimits.valid_venue?("ab")
      assert OutcomeDeployerLimits.valid_venue?("abcd")
      refute OutcomeDeployerLimits.valid_venue?("a")
      refute OutcomeDeployerLimits.valid_venue?("abcde")
      refute OutcomeDeployerLimits.valid_venue?("ABC")
      refute OutcomeDeployerLimits.valid_venue?(nil)
    end
  end

  describe "outcomeDeployerLimits" do
    test "passes the untyped response through" do
      assert {:ok, limits} =
               %{"remaining_daily" => 42, "remaining_active" => 3}
               |> OutcomeDeployerLimits.preprocess()
               |> OutcomeDeployerLimits.parse_response()

      assert limits.data == %{"remaining_daily" => 42, "remaining_active" => 3}
    end
  end
end
