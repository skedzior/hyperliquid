defmodule Hyperliquid.Api.Exchange.ActionOrderingTest do
  @moduledoc """
  H3: the msgpack action hash is order sensitive, so the canonical key order has
  to survive whatever the action builders do with plain maps.

  `test/signing_vectors_test.exs` proves the order is *correct* (cross-SDK
  vectors). This file proves it is *reachable* from the modules — including the
  deploy variants, whose actions are built as nested plain maps and carry
  `{coin, value}` tuple lists that `Jason` cannot encode at all.
  """

  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.{Action, Order, PerpDeploy, SpotDeploy}

  @private_key "0000000000000000000000000000000000000000000000000000000000000001"

  setup do
    bypass = Bypass.open()
    Application.put_env(:hyperliquid, :http_url, "http://localhost:#{bypass.port}")

    Bypass.stub(bypass, "POST", "/info", fn conn ->
      Plug.Conn.put_resp_header(conn, "content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{}))
    end)

    {:ok, bypass: bypass}
  end

  defp capture(bypass, fun) do
    parent = self()

    Bypass.expect(bypass, "POST", "/exchange", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:body, body})

      Plug.Conn.put_resp_header(conn, "content-type", "application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
      )
    end)

    assert {:ok, %{"status" => "ok"}} = fun.()
    assert_receive {:body, body}
    body
  end

  defp action_json(body) do
    # The action is re-encoded from the decoded body only to locate it; assert on
    # the raw slice so key order is observable.
    [_, action] = Regex.run(~r/"action":(.*),"nonce"/U, body)
    action
  end

  describe "perpDeploy (nested plain maps)" do
    test "registerAsset2 nests in the schema's declared order", %{bypass: bypass} do
      raw =
        capture(bypass, fn ->
          PerpDeploy.register_asset2(
            %{
              max_gas: 1_000_000,
              asset_request: %{
                coin: "MYTOKEN",
                sz_decimals: 2,
                oracle_px: "1.5",
                margin_table_id: 10,
                margin_mode: "normal"
              },
              dex: "mydex",
              schema: %{full_name: "My Token", collateral_token: 0, oracle_updater: nil}
            },
            private_key: @private_key
          )
        end)

      assert action_json(raw) ==
               ~s({"type":"perpDeploy","registerAsset2":{"maxGas":1000000,) <>
                 ~s("assetRequest":{"coin":"MYTOKEN","szDecimals":2,"oraclePx":"1.5",) <>
                 ~s("marginTableId":10,"marginMode":"normal"},"dex":"mydex",) <>
                 ~s("schema":{"fullName":"My Token","collateralToken":0,"oracleUpdater":null}}})
    end

    test "setSubDeployers orders the nested list objects", %{bypass: bypass} do
      raw =
        capture(bypass, fn ->
          PerpDeploy.set_sub_deployers(
            "mydex",
            [
              %{
                variant: "oracleUpdater",
                user: "0x0000000000000000000000000000000000000001",
                allowed: true
              }
            ],
            private_key: @private_key
          )
        end)

      assert action_json(raw) ==
               ~s({"type":"perpDeploy","setSubDeployers":{"dex":"mydex","subDeployers":) <>
                 ~s([{"variant":"oracleUpdater",) <>
                 ~s("user":"0x0000000000000000000000000000000000000001","allowed":true}]}})
    end

    test "setPerpAnnotation keeps its five fields in order", %{bypass: bypass} do
      raw =
        capture(bypass, fn ->
          PerpDeploy.set_perp_annotation(
            %{
              coin: "MYTOKEN",
              category: "meme",
              description: "a token",
              display_name: nil,
              keywords: ["a", "b"]
            },
            private_key: @private_key
          )
        end)

      assert action_json(raw) ==
               ~s({"type":"perpDeploy","setPerpAnnotation":{"coin":"MYTOKEN",) <>
                 ~s("category":"meme","description":"a token","displayName":null,) <>
                 ~s("keywords":["a","b"]}})
    end
  end

  describe "tuple-list deploy params" do
    # `[{coin, value}]` is the documented Elixir-side shape. `Jason` raises on a
    # bare tuple, so before the ordering layer converted them these actions could
    # not be encoded at all.
    test "setFundingMultipliers encodes tuples as two-element arrays", %{bypass: bypass} do
      raw =
        capture(bypass, fn ->
          PerpDeploy.set_funding_multipliers([{"AAA", "1.5"}, {"BBB", "2"}],
            private_key: @private_key
          )
        end)

      assert action_json(raw) ==
               ~s({"type":"perpDeploy","setFundingMultipliers":[["AAA","1.5"],["BBB","2"]]})
    end

    test "setMarginTableIds / setOpenInterestCaps / setGrowthModes accept tuples", %{
      bypass: bypass
    } do
      assert action_json(
               capture(bypass, fn ->
                 PerpDeploy.set_margin_table_ids([{"AAA", 3}], private_key: @private_key)
               end)
             ) == ~s({"type":"perpDeploy","setMarginTableIds":[["AAA",3]]})

      assert action_json(
               capture(bypass, fn ->
                 PerpDeploy.set_open_interest_caps([{"AAA", 1_000_000}],
                   private_key: @private_key
                 )
               end)
             ) == ~s({"type":"perpDeploy","setOpenInterestCaps":[["AAA",1000000]]})

      assert action_json(
               capture(bypass, fn ->
                 PerpDeploy.set_growth_modes([{"AAA", true}], private_key: @private_key)
               end)
             ) == ~s({"type":"perpDeploy","setGrowthModes":[["AAA",true]]})
    end
  end

  describe "spotDeploy (nested plain maps)" do
    test "registerToken2 nests spec before maxGas", %{bypass: bypass} do
      raw =
        capture(bypass, fn ->
          SpotDeploy.register_token2(
            %{
              spec: %{name: "MYTOKEN", sz_decimals: 2, wei_decimals: 8},
              max_gas: 1_000_000,
              full_name: "My Token"
            },
            private_key: @private_key
          )
        end)

      assert action_json(raw) ==
               ~s({"type":"spotDeploy","registerToken2":{"spec":{"name":"MYTOKEN",) <>
                 ~s("szDecimals":2,"weiDecimals":8},"maxGas":1000000,"fullName":"My Token"}})
    end

    test "registerHyperliquidity keeps its five fields in order", %{bypass: bypass} do
      raw =
        capture(bypass, fn ->
          SpotDeploy.register_hyperliquidity(
            %{spot: 1, start_px: "1.0", order_sz: "10", n_orders: 5, n_seeded_levels: 2},
            private_key: @private_key
          )
        end)

      assert action_json(raw) ==
               ~s({"type":"spotDeploy","registerHyperliquidity":{"spot":1,"startPx":"1.0",) <>
                 ~s("orderSz":"10","nOrders":5,"nSeededLevels":2}})
    end
  end

  describe "priority grouping signs (H2)" do
    # The old typed Rust `Actions` enum declared `grouping` as a string and
    # rejected `{"p": n}` with "invalid type: map, expected a string". Every L1
    # action now takes the generic ordered-msgpack path, so it signs.
    test "an order with {\"p\": n} grouping round-trips through signing", %{bypass: bypass} do
      raw =
        capture(bypass, fn ->
          Order.place_batch([Order.limit(0, true, "100", "1")], {:priority, 50_000_000},
            private_key: @private_key
          )
        end)

      assert action_json(raw) =~ ~s("grouping":{"p":50000000})
      assert %{"signature" => %{"r" => _, "s" => _, "v" => _}} = Jason.decode!(raw)
    end
  end

  describe "Action.ordered/1" do
    test "large maps (> 32 keys, hash-order iteration) are still canonicalized" do
      big = for i <- 1..40, into: %{}, do: {"z#{i}", i}
      action = Map.merge(big, %{"grouping" => "na", "orders" => [], "type" => "order"})

      encoded = action |> Action.ordered() |> Jason.encode!()

      assert String.starts_with?(encoded, ~s({"type":"order","orders":[],"grouping":"na",))
    end

    test "keys the schema does not declare are preserved, not dropped" do
      action = %{"type" => "noop", "someFutureField" => 1}
      decoded = action |> Action.ordered() |> Jason.encode!() |> Jason.decode!()

      assert decoded == %{"type" => "noop", "someFutureField" => 1}
    end

    test "atom and string keys are both accepted and keep their own type" do
      assert %{type: "cancel", cancels: [%{o: 1, a: 0}]}
             |> Action.ordered()
             |> Jason.encode!() == ~s({"type":"cancel","cancels":[{"a":0,"o":1}]})
    end

    test "hex values are lower-cased so the exchange re-hashes identical bytes" do
      # Hyperliquid lower-cases every `0x…` string when it deserializes the
      # action into its own structs, and the signature is checked against that
      # re-serialization. A checksummed address on the wire therefore recovers
      # a garbage signer ("User or API Wallet 0x… does not exist"). Verified
      # live on testnet 2026-09-09 with `reserveRequestWeight`.
      assert %{
               type: "reserveRequestWeight",
               weight: 1,
               destination: "0x7A588B92433FF4B9991B8B56a8fD0Db9649E66F2"
             }
             |> Action.ordered()
             |> Jason.encode!() ==
               ~s({"type":"reserveRequestWeight","weight":1,"destination":"0x7a588b92433ff4b9991b8b56a8fd0db9649e66f2"})
    end

    test "hex values nested in arrays and undeclared keys are lower-cased too" do
      encoded =
        %{
          "type" => "outcomeDeploy",
          "venue" => "abcd",
          "operation" => %{
            "setSubDeployers" => [
              %{
                "variant" => "settleOutcome",
                "user" => "0xAbCdEf0123456789AbCdEf0123456789AbCdEf01",
                "allowed" => false
              }
            ]
          }
        }
        |> Action.ordered()
        |> Jason.encode!()

      assert encoded =~ ~s("user":"0xabcdef0123456789abcdef0123456789abcdef01")
      refute encoded =~ "AbCdEf"
    end

    test "a cloid keeps its position and is lower-cased" do
      assert %{
               type: "cancelByCloid",
               cancels: [%{asset: 0, cloid: "0xABCD1234ABCD1234ABCD1234ABCD1234"}]
             }
             |> Action.ordered()
             |> Jason.encode!() ==
               ~s({"type":"cancelByCloid","cancels":[{"asset":0,"cloid":"0xabcd1234abcd1234abcd1234abcd1234"}]})
    end

    test "non-hex strings keep their case" do
      assert %{type: "setDisplayName", displayName: "MixedCase Name"}
             |> Action.ordered()
             |> Jason.encode!() == ~s({"type":"setDisplayName","displayName":"MixedCase Name"})
    end

    test "an unknown action type is still emitted deterministically" do
      assert %{"type" => "notAnAction", "b" => 1}
             |> Action.ordered()
             |> Jason.encode!()
             |> Jason.decode!() == %{"type" => "notAnAction", "b" => 1}
    end
  end
end
