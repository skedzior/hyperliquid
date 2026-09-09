defmodule Hyperliquid.Api.Exchange.OrderGroupingExtraTest do
  @moduledoc """
  Covers the priority-rate grouping (`{"p": n}`) and the `:extra` trigger passthrough
  seam used for not-yet-documented order fields (e.g. trailing stops).

  These assert the built action map directly via `Order.build_action/3` — no signing,
  no network. The signing round-trip for `{"p": n}` grouping (which the old typed
  Rust `Actions` enum rejected, because it declared `grouping` as a string) lives in
  `test/api/exchange/action_ordering_test.exs`.
  """

  use ExUnit.Case, async: true

  alias Hyperliquid.Api.Exchange.Order

  defp limit_order, do: Order.limit(0, true, "100", "1")

  describe "grouping" do
    test "string groupings are unchanged" do
      for {input, expected} <- [
            {:na, "na"},
            {:normal_tpsl, "normalTpsl"},
            {:position_tpsl, "positionTpsl"}
          ] do
        assert Order.build_action([limit_order()], input, nil).grouping == expected
      end
    end

    test "{:priority, p} emits %{p: p}" do
      assert Order.build_action([limit_order()], {:priority, 12_345}, nil).grouping ==
               %{p: 12_345}
    end

    test "%{p: p} map form is accepted" do
      assert Order.build_action([limit_order()], %{p: 0}, nil).grouping == %{p: 0}
    end

    test "encodes as {\"p\": n} on the wire" do
      action = Order.build_action([limit_order()], {:priority, 80_000}, nil)
      assert Jason.decode!(Jason.encode!(action))["grouping"] == %{"p" => 80_000}
    end

    test "accepts the raised 100% cap" do
      assert Order.build_action([limit_order()], {:priority, 100_000_000}, nil).grouping ==
               %{p: 100_000_000}
    end

    test "rejects p above 100_000_000 or negative" do
      for bad <- [100_000_001, -1] do
        assert_raise ArgumentError, fn ->
          Order.build_action([limit_order()], {:priority, bad}, nil)
        end
      end
    end
  end

  describe "trigger :extra passthrough" do
    defp trigger_wire(order) do
      %{orders: [%{t: %{trigger: trigger}}]} = Order.build_action([order], :na, nil)
      trigger
    end

    test "trigger order without :extra is unchanged" do
      trigger = trigger_wire(Order.trigger(0, false, "48000", "0.1", "49000", tpsl: "sl"))

      assert trigger == %{isMarket: true, triggerPx: "49000", tpsl: "sl"}
    end

    test ":extra keys are merged verbatim into t.trigger" do
      trigger =
        trigger_wire(
          Order.trigger(0, false, "48000", "0.1", "49000",
            tpsl: "sl",
            extra: %{"someUnpublishedField" => "1.5"}
          )
        )

      # Nothing renamed, nothing invented — the caller's keys pass straight through.
      assert trigger["someUnpublishedField"] == "1.5"
      assert trigger.isMarket == true
      assert trigger.triggerPx == "49000"
      assert trigger.tpsl == "sl"
    end

    test "an empty :extra map changes nothing" do
      trigger = trigger_wire(Order.trigger(0, false, "48000", "0.1", "49000", extra: %{}))
      assert map_size(trigger) == 3
    end

    test "a limit order is unaffected by the seam" do
      %{orders: [order]} = Order.build_action([limit_order()], :na, nil)
      assert order.t == %{limit: %{tif: "Gtc"}}
    end
  end
end
