defmodule Hyperliquid.Api.Exchange.OutcomeDeployTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.OutcomeDeploy

  # These tests assert the exact JSON emitted for each `outcomeDeploy` operation.
  # Shape source: the official HIP-4 deployer-actions page — the action is TOP-LEVEL
  # with a required top-level `venue`, NOT nested under `spotDeploy` (which is what
  # @nktkas/hyperliquid v0.33.3 still emits).

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

  # Captures the raw request body (key order intact) for one exchange call.
  defp capture_action(bypass, fun) do
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

    # Extract the raw `"action":{...}` text so key order can be asserted exactly.
    action_json = extract_action(body)
    {action_json, Jason.decode!(body)["action"]}
  end

  describe "registerStandaloneOutcomeFromTemplate" do
    test "top-level venue, sorted keywordToValue, deployerFeeScale", %{bypass: bypass} do
      {raw, action} =
        capture_action(bypass, fn ->
          OutcomeDeploy.register_standalone_outcome_from_template(
            "abcd",
            %{
              id: "tpl-1",
              # deliberately unsorted — must be emitted sorted by keyword
              keyword_to_value: [["zeta", "Z"], ["alpha", "A"]],
              deployer_fee_scale: "1.5"
            },
            private_key: @private_key
          )
        end)

      assert raw ==
               ~s({"type":"outcomeDeploy","venue":"abcd","operation":) <>
                 ~s({"registerStandaloneOutcomeFromTemplate":{"id":"tpl-1",) <>
                 ~s("keywordToValue":[["alpha","A"],["zeta","Z"]],"deployerFeeScale":"1.5"}}})

      # venue is a sibling of operation, never inside it
      assert action["venue"] == "abcd"
      refute Map.has_key?(action["operation"]["registerStandaloneOutcomeFromTemplate"], "venue")
    end
  end

  describe "registerQuestionFromTemplate" do
    test "question instance carries the fee scale, named outcomes do not", %{bypass: bypass} do
      {raw, _action} =
        capture_action(bypass, fn ->
          OutcomeDeploy.register_question_from_template(
            "hlq",
            %{
              question_template_instance: %{
                id: "q-1",
                keyword_to_value: [["b", "2"], ["a", "1"]],
                deployer_fee_scale: "0"
              },
              named_outcome_template_instances: [
                %{id: "o-1", keyword_to_value: [["name", "Alice"]]}
              ]
            },
            private_key: @private_key
          )
        end)

      assert raw ==
               ~s({"type":"outcomeDeploy","venue":"hlq","operation":) <>
                 ~s({"registerQuestionFromTemplate":{"questionTemplateInstance":) <>
                 ~s({"id":"q-1","keywordToValue":[["a","1"],["b","2"]],"deployerFeeScale":"0"},) <>
                 ~s("namedOutcomeTemplateInstances":) <>
                 ~s([{"id":"o-1","keywordToValue":[["name","Alice"]]}]}}})
    end
  end

  describe "registerAndAssociateNamedOutcomeFromTemplate" do
    test "emits question index plus a single named outcome instance", %{bypass: bypass} do
      {raw, _} =
        capture_action(bypass, fn ->
          OutcomeDeploy.register_and_associate_named_outcome_from_template(
            "abcd",
            %{question: 7, named_outcome_template_instance: %{id: "o-2", keyword_to_value: []}},
            private_key: @private_key
          )
        end)

      assert raw ==
               ~s({"type":"outcomeDeploy","venue":"abcd","operation":) <>
                 ~s({"registerAndAssociateNamedOutcomeFromTemplate":) <>
                 ~s({"question":7,"namedOutcomeTemplateInstance":{"id":"o-2","keywordToValue":[]}}}})
    end
  end

  describe "settleOutcome" do
    test "emits outcome, settleFraction, empty details, nameAndDescription, sideNames", %{
      bypass: bypass
    } do
      {raw, _} =
        capture_action(bypass, fn ->
          OutcomeDeploy.settle_outcome(
            "abcd",
            %{
              outcome: 95,
              settle_fraction: "1",
              name_and_description: ["Name", "Desc"],
              side_names: ["Yes", "No"]
            },
            private_key: @private_key
          )
        end)

      assert raw ==
               ~s({"type":"outcomeDeploy","venue":"abcd","operation":) <>
                 ~s({"settleOutcome":{"outcome":95,"settleFraction":"1","details":"",) <>
                 ~s("nameAndDescription":["Name","Desc"],"sideNames":["Yes","No"]}}})
    end
  end

  describe "settleQuestion2" do
    test "wraps a list of settlement objects", %{bypass: bypass} do
      {raw, _} =
        capture_action(bypass, fn ->
          OutcomeDeploy.settle_question2(
            "abcd",
            %{
              question: 3,
              outcome_settlements: [
                %{
                  outcome: 10,
                  settle_fraction: "0",
                  name_and_description: ["N", "D"],
                  side_names: ["Y", "N"]
                }
              ],
              name_and_description: ["QN", "QD"]
            },
            private_key: @private_key
          )
        end)

      assert raw ==
               ~s({"type":"outcomeDeploy","venue":"abcd","operation":) <>
                 ~s({"settleQuestion2":{"question":3,"outcomeSettlements":) <>
                 ~s([{"outcome":10,"settleFraction":"0","details":"",) <>
                 ~s("nameAndDescription":["N","D"],"sideNames":["Y","N"]}],) <>
                 ~s("nameAndDescription":["QN","QD"]}}})
    end
  end

  describe "setSubDeployers" do
    test "payload is a bare list of {variant, user, allowed}", %{bypass: bypass} do
      {raw, _} =
        capture_action(bypass, fn ->
          OutcomeDeploy.set_sub_deployers(
            "abcd",
            [
              %{
                variant: "settleOutcome",
                user: "0x0000000000000000000000000000000000000001",
                allowed: true
              }
            ],
            private_key: @private_key
          )
        end)

      assert raw ==
               ~s({"type":"outcomeDeploy","venue":"abcd","operation":) <>
                 ~s({"setSubDeployers":[{"variant":"settleOutcome",) <>
                 ~s("user":"0x0000000000000000000000000000000000000001","allowed":true}]}})
    end

    test "rejects an unknown sub-deployer variant" do
      assert_raise ArgumentError, fn ->
        OutcomeDeploy.set_sub_deployers(
          "abcd",
          [%{variant: "notAVariant", user: "0x1", allowed: true}],
          private_key: @private_key
        )
      end
    end
  end

  describe "validation" do
    test "rejects venues that are not 2-4 lowercase ASCII letters" do
      for bad <- ["a", "abcde", "ABCD", "ab1", "", "ab-c"] do
        assert_raise ArgumentError, fn ->
          OutcomeDeploy.build_action(bad, Jason.OrderedObject.new([]))
        end
      end
    end

    test "accepts 2, 3 and 4 letter venues" do
      for good <- ["ab", "abc", "abcd"] do
        assert %Jason.OrderedObject{} =
                 OutcomeDeploy.build_action(good, Jason.OrderedObject.new([]))
      end
    end

    test "rejects deployerFeeScale outside [0, 10]" do
      assert_raise ArgumentError, fn ->
        OutcomeDeploy.register_standalone_outcome_from_template(
          "abcd",
          %{id: "t", keyword_to_value: [], deployer_fee_scale: "10.5"},
          private_key: @private_key
        )
      end
    end

    test "rejects settleFraction outside [0, 1]" do
      assert_raise ArgumentError, fn ->
        OutcomeDeploy.settle_outcome(
          "abcd",
          %{
            outcome: 1,
            settle_fraction: "1.5",
            name_and_description: ["N", "D"],
            side_names: ["Y", "N"]
          },
          private_key: @private_key
        )
      end
    end

    test "rejects non-empty settlement details" do
      assert_raise ArgumentError, fn ->
        OutcomeDeploy.settle_outcome(
          "abcd",
          %{
            outcome: 1,
            settle_fraction: "1",
            details: "nope",
            name_and_description: ["N", "D"],
            side_names: ["Y", "N"]
          },
          private_key: @private_key
        )
      end
    end

    test "rejects keyword values over 100 chars or containing braces" do
      for bad <- [String.duplicate("x", 101), "has {brace}"] do
        assert_raise ArgumentError, fn ->
          OutcomeDeploy.register_standalone_outcome_from_template(
            "abcd",
            %{id: "t", keyword_to_value: [["k", bad]], deployer_fee_scale: "1"},
            private_key: @private_key
          )
        end
      end
    end

    test "rejects more than 100 named outcome instances" do
      instances =
        for i <- 1..101, do: %{id: "o-#{i}", keyword_to_value: []}

      assert_raise ArgumentError, fn ->
        OutcomeDeploy.register_question_from_template(
          "abcd",
          %{
            question_template_instance: %{
              id: "q",
              keyword_to_value: [],
              deployer_fee_scale: "1"
            },
            named_outcome_template_instances: instances
          },
          private_key: @private_key
        )
      end
    end
  end

  # Extracts the exact `action` JSON text from the request body so key order can be
  # asserted. The surrounding payload map's key order is not stable, so scan balanced
  # braces rather than matching on neighbouring keys.
  defp extract_action(body) do
    {start, len} = :binary.match(body, "\"action\":")
    rest = binary_part(body, start + len, byte_size(body) - start - len)
    take_object(rest)
  end

  defp take_object(bin) do
    {len, _, _, _} =
      bin
      |> :binary.bin_to_list()
      |> Enum.reduce_while({0, 0, false, false}, fn ch, {i, depth, in_str, esc} ->
        cond do
          esc -> {:cont, {i + 1, depth, in_str, false}}
          in_str and ch == ?\\ -> {:cont, {i + 1, depth, true, true}}
          ch == ?" -> {:cont, {i + 1, depth, not in_str, false}}
          in_str -> {:cont, {i + 1, depth, true, false}}
          ch == ?{ -> {:cont, {i + 1, depth + 1, false, false}}
          ch == ?} and depth == 1 -> {:halt, {i + 1, 0, false, false}}
          ch == ?} -> {:cont, {i + 1, depth - 1, false, false}}
          true -> {:cont, {i + 1, depth, false, false}}
        end
      end)

    binary_part(bin, 0, len)
  end
end
