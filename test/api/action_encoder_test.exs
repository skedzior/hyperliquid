defmodule Hyperliquid.Api.ActionEncoderTest do
  use ExUnit.Case, async: true

  alias Hyperliquid.Api.ActionEncoder
  alias Hyperliquid.Signer

  @nonce 1_234_567_890

  # Expected hashes are produced by the reference Python SDK
  # (hyperliquid/utils/signing.py action_hash/4) over the same action, and the
  # expected JSON is that action's canonical wire form. Regenerate with:
  #
  #   msgpack.packb(action) + nonce.to_bytes(8, "big") + b"\x00"  |> keccak
  #
  # A map whose keys are shuffled must still produce these values — that is the
  # whole point of the encoder.
  @vectors [
    %{
      name: "limit order",
      action: %{
        type: "order",
        orders: [%{a: 0, b: true, p: "30000", s: "0.1", r: false, t: %{limit: %{tif: "Gtc"}}}],
        grouping: "na"
      },
      json:
        ~s({"type":"order","orders":[{"a":0,"b":true,"p":"30000","s":"0.1","r":false,"t":{"limit":{"tif":"Gtc"}}}],"grouping":"na"}),
      hash: "0x25367e0dba84351148288c2233cd6130ed6cec5967ded0c0b7334f36f957cc90"
    },
    %{
      name: "trigger order with cloid",
      action: %{
        type: "order",
        orders: [
          %{
            a: 1,
            b: false,
            p: "2000",
            s: "1.5",
            r: true,
            t: %{trigger: %{isMarket: true, triggerPx: "1900", tpsl: "sl"}},
            c: "0x00000000000000000000000000000001"
          }
        ],
        grouping: "positionTpsl"
      },
      json:
        ~s({"type":"order","orders":[{"a":1,"b":false,"p":"2000","s":"1.5","r":true,"t":{"trigger":{"isMarket":true,"triggerPx":"1900","tpsl":"sl"}},"c":"0x00000000000000000000000000000001"}],"grouping":"positionTpsl"}),
      hash: "0xb766c68be453692b3d9779aba2240d66120f41c7a85694bed5cb6befc934fd93"
    },
    %{
      name: "order with builder fee",
      action: %{
        type: "order",
        orders: [%{a: 0, b: true, p: "30000", s: "0.1", r: false, t: %{limit: %{tif: "Alo"}}}],
        grouping: "na",
        builder: %{b: "0x1234567890123456789012345678901234567890", f: 10}
      },
      json:
        ~s({"type":"order","orders":[{"a":0,"b":true,"p":"30000","s":"0.1","r":false,"t":{"limit":{"tif":"Alo"}}}],"grouping":"na","builder":{"b":"0x1234567890123456789012345678901234567890","f":10}}),
      hash: "0x2f6ef896c84f31afd555b399fa0b2210512f584a3ada2e0d3ad40bbfa3a1a061"
    },
    %{
      name: "order with priority-rate grouping",
      action: %{
        type: "order",
        orders: [%{a: 0, b: true, p: "30000", s: "0.1", r: false, t: %{limit: %{tif: "Ioc"}}}],
        grouping: %{p: 12345}
      },
      json:
        ~s({"type":"order","orders":[{"a":0,"b":true,"p":"30000","s":"0.1","r":false,"t":{"limit":{"tif":"Ioc"}}}],"grouping":{"p":12345}}),
      hash: "0x5e5d85104254d23a41f4efbbec00cef8157e46539c9c5c5be94d0ae43d20b6f6"
    },
    %{
      name: "cancel",
      action: %{type: "cancel", cancels: [%{a: 5, o: 123_456}]},
      json: ~s({"type":"cancel","cancels":[{"a":5,"o":123456}]}),
      hash: "0x070d69a789ee062b848ffb205726f6e38de6bc0fbc617100a6d251cb022734f9"
    },
    %{
      name: "updateLeverage",
      action: %{type: "updateLeverage", asset: 3, isCross: true, leverage: 20},
      json: ~s({"type":"updateLeverage","asset":3,"isCross":true,"leverage":20}),
      hash: "0xb30ee378f9f3e63644413f8fea01ded8bfefdfe555ae437add208718857ac661"
    },
    %{
      name: "scheduleCancel",
      action: %{type: "scheduleCancel", time: 1_735_689_600_000},
      json: ~s({"type":"scheduleCancel","time":1735689600000}),
      hash: "0x3a66628d6aee0f0234d97afedeac15d09b6a753f864d2f03b6396d5fee9d8182"
    }
  ]

  describe "canonical encoding matches the reference implementation" do
    for %{name: name} = vector <- @vectors do
      @vector vector

      test "#{name}: encodes to canonical wire JSON" do
        assert {:ok, json} = ActionEncoder.encode(@vector.action)
        assert json == @vector.json
      end

      test "#{name}: hashes to the reference connection id" do
        assert {:ok, json} = ActionEncoder.encode(@vector.action)
        assert Signer.compute_connection_id_ex(json, @nonce, nil, nil) == @vector.hash
      end
    end
  end

  describe "determinism" do
    test "key insertion order does not affect the encoding" do
      # Same order, built with the keys inserted back to front.
      shuffled =
        Enum.reduce(
          [
            {:t, %{limit: %{tif: "Gtc"}}},
            {:r, false},
            {:s, "0.1"},
            {:p, "30000"},
            {:b, true},
            {:a, 0}
          ],
          %{},
          fn {k, v}, acc -> Map.put(acc, k, v) end
        )

      action = %{grouping: "na", orders: [shuffled], type: "order"}

      assert {:ok, json} = ActionEncoder.encode(action)

      assert json ==
               ~s({"type":"order","orders":[{"a":0,"b":true,"p":"30000","s":"0.1","r":false,"t":{"limit":{"tif":"Gtc"}}}],"grouping":"na"})
    end

    test "string and atom keys encode identically" do
      atoms = %{type: "cancel", cancels: [%{a: 5, o: 123_456}]}
      strings = %{"type" => "cancel", "cancels" => [%{"a" => 5, "o" => 123_456}]}

      assert ActionEncoder.encode(atoms) == ActionEncoder.encode(strings)
    end

    test "unknown keys are ordered deterministically after known ones" do
      action = %{type: "someFutureAction", zeta: 1, alpha: 2, mid: 3}

      assert {:ok, json} = ActionEncoder.encode(action)
      assert json == ~s({"type":"someFutureAction","alpha":2,"mid":3,"zeta":1})
    end

    test "repeated encodings of the same action are stable" do
      action = %{
        type: "order",
        orders: [%{a: 0, b: true, p: "30000", s: "0.1", r: false, t: %{limit: %{tif: "Gtc"}}}],
        grouping: "na"
      }

      encodings = for _ <- 1..50, do: ActionEncoder.encode(action)
      assert encodings |> Enum.uniq() |> length() == 1
    end
  end

  describe "field_order/0" do
    test "contains no duplicate keys" do
      order = ActionEncoder.field_order()
      assert length(order) == order |> Enum.uniq() |> length()
    end

    test "covers every key used by the reference vectors" do
      known = MapSet.new(ActionEncoder.field_order())

      used =
        @vectors
        |> Enum.flat_map(fn %{action: action} -> collect_keys(action) end)
        |> MapSet.new()

      assert MapSet.subset?(used, known),
             "unranked keys: #{inspect(MapSet.difference(used, known) |> MapSet.to_list())}"
    end
  end

  defp collect_keys(map) when is_map(map) and not is_struct(map) do
    Enum.flat_map(map, fn {k, v} ->
      [to_string(k) | collect_keys(v)]
    end)
  end

  defp collect_keys(list) when is_list(list), do: Enum.flat_map(list, &collect_keys/1)
  defp collect_keys(_), do: []
end
