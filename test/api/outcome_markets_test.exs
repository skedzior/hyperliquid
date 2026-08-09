defmodule Hyperliquid.Api.OutcomeMarketsTest do
  @moduledoc """
  Coverage for the HIP-4 prediction market endpoints.
  """
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.{ActivateOutcomeDeployer, UserOutcome}
  alias Hyperliquid.Api.Info.{OutcomeMeta, OutcomeTemplates, SettledOutcome}
  alias Hyperliquid.Api.Subscription.OutcomeMetaUpdates

  @private_key "0x822e9959e022b78423eb653a62ea0020cd283e71a2a8133a6ff2aeffaf373cff"

  setup do
    bypass = Bypass.open()
    prev_url = Application.get_env(:hyperliquid, :http_url)
    Application.put_env(:hyperliquid, :http_url, "http://localhost:#{bypass.port}")

    on_exit(fn ->
      if prev_url,
        do: Application.put_env(:hyperliquid, :http_url, prev_url),
        else: Application.delete_env(:hyperliquid, :http_url)
    end)

    {:ok, bypass: bypass}
  end

  defp respond(bypass, path, capture_to, body) do
    Bypass.expect(bypass, "POST", path, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      if capture_to, do: send(capture_to, {:request, Jason.decode!(raw)})

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(body))
    end)
  end

  describe "outcomeMeta" do
    test "parses outcomes and questions", %{bypass: bypass} do
      respond(bypass, "/info", self(), %{
        "outcomes" => [
          %{
            "outcome" => 7,
            "name" => "ABC above 100",
            "description" => "Resolves YES if ABC > 100",
            "sideSpecs" => [%{"name" => "YES", "token" => 42}, %{"name" => "NO", "token" => 43}],
            "quoteToken" => "USDC",
            "deployer" => "0x1234567890123456789012345678901234567890"
          }
        ],
        "questions" => [
          %{
            "question" => 3,
            "name" => "Where does ABC land?",
            "description" => "",
            "fallbackOutcome" => 9,
            "namedOutcomes" => [7, 8],
            "settledNamedOutcomes" => [7]
          }
        ]
      })

      assert {:ok, meta} = OutcomeMeta.request()

      assert_receive {:request, request}
      assert request["type"] == "outcomeMeta"

      assert {:ok, outcome} = OutcomeMeta.find_outcome(meta, 7)
      assert outcome.name == "ABC above 100"
      assert outcome.quote_token == "USDC"
      assert length(outcome.side_specs) == 2

      assert {:ok, question} = OutcomeMeta.find_question(meta, 3)
      assert question.fallback_outcome == 9
      refute OutcomeMeta.question_settled?(question)

      assert {:error, :not_found} = OutcomeMeta.find_outcome(meta, 999)
    end

    test "question_settled? is true once every named outcome settled" do
      assert OutcomeMeta.question_settled?(%{
               named_outcomes: [7, 8],
               settled_named_outcomes: [7, 8]
             })

      refute OutcomeMeta.question_settled?(%{named_outcomes: [], settled_named_outcomes: []})
    end

    test "by_deployer filters case-insensitively", %{bypass: bypass} do
      respond(bypass, "/info", nil, %{
        "outcomes" => [
          %{
            "outcome" => 1,
            "name" => "a",
            "deployer" => "0xAABBCCDDEEFF00112233445566778899AABBCCDD"
          },
          %{"outcome" => 2, "name" => "b"}
        ],
        "questions" => []
      })

      assert {:ok, meta} = OutcomeMeta.request()

      assert [%{outcome: 1}] =
               OutcomeMeta.by_deployer(meta, "0xaabbccddeeff00112233445566778899aabbccdd")
    end
  end

  describe "outcomeTemplates" do
    test "wraps the bare array response", %{bypass: bypass} do
      respond(bypass, "/info", self(), [
        %{
          "id" => "above-target",
          "role" => %{"standaloneOutcome" => %{"sideNames" => ["YES", "NO"]}},
          "name" => "{underlying} above {target} at {expiry}",
          "description" => "",
          "keywords" => [["underlying", "hlPerp"], ["target", "string"], ["expiry", "dateTime"]]
        }
      ])

      assert {:ok, templates} = OutcomeTemplates.request()

      assert_receive {:request, request}
      assert request["type"] == "outcomeTemplates"

      assert {:ok, template} = OutcomeTemplates.find(templates, "above-target")
      assert OutcomeTemplates.keyword_names(template) == ["underlying", "target", "expiry"]
      assert {:error, :not_found} = OutcomeTemplates.find(templates, "nope")
    end

    test "keyword_to_value sorts pairs lexicographically" do
      assert OutcomeTemplates.keyword_to_value(%{
               "underlying" => "ABC",
               "expiry" => "20260801-0600",
               "target" => "100"
             }) == [["expiry", "20260801-0600"], ["target", "100"], ["underlying", "ABC"]]
    end
  end

  describe "settledOutcome" do
    test "parses a settled outcome", %{bypass: bypass} do
      respond(bypass, "/info", self(), %{
        "spec" => %{"outcome" => 7, "name" => "ABC above 100"},
        "settleFraction" => "1",
        "details" => "settled by oracle"
      })

      assert {:ok, settled} = SettledOutcome.request(7)

      assert_receive {:request, request}
      assert request["type"] == "settledOutcome"
      assert request["outcome"] == 7

      assert SettledOutcome.settled?(settled)
      assert {:ok, 1.0} = SettledOutcome.settle_fraction(settled)
      assert SettledOutcome.resolved_yes?(settled)
    end

    test "handles the null response for an unsettled outcome", %{bypass: bypass} do
      respond(bypass, "/info", nil, nil)

      assert {:ok, settled} = SettledOutcome.request(7)
      refute SettledOutcome.settled?(settled)
      assert {:error, :not_settled} = SettledOutcome.settle_fraction(settled)
      refute SettledOutcome.resolved_yes?(settled)
    end
  end

  describe "activateOutcomeDeployer" do
    test "activate sends the venue name", %{bypass: bypass} do
      respond(bypass, "/exchange", self(), %{"status" => "ok"})

      assert {:ok, _} = ActivateOutcomeDeployer.activate("abcd", private_key: @private_key)

      assert_receive {:request, request}
      assert request["action"]["type"] == "activateOutcomeDeployer"
      assert request["action"]["activate"] == %{"venueName" => "abcd"}
    end

    test "deactivate sends a null deactivate variant", %{bypass: bypass} do
      respond(bypass, "/exchange", self(), %{"status" => "ok"})

      assert {:ok, _} = ActivateOutcomeDeployer.deactivate(private_key: @private_key)

      assert_receive {:request, request}
      assert request["action"]["type"] == "activateOutcomeDeployer"
      assert Map.has_key?(request["action"], "deactivate")
      assert request["action"]["deactivate"] == nil
    end

    test "rejects venue names outside 2-4 lowercase letters" do
      for bad <- ["a", "abcde", "ABCD", "ab1", "", "a-b"] do
        assert_raise ArgumentError, ~r/2-4 lowercase ASCII letters/, fn ->
          ActivateOutcomeDeployer.activate(bad, private_key: @private_key)
        end
      end
    end
  end

  describe "userOutcome" do
    test "split_outcome sends the splitOutcome variant", %{bypass: bypass} do
      respond(bypass, "/exchange", self(), %{"status" => "ok"})

      assert {:ok, _} = UserOutcome.split_outcome(7, "1", private_key: @private_key)

      assert_receive {:request, request}
      assert request["action"]["type"] == "userOutcome"
      assert request["action"]["splitOutcome"] == %{"outcome" => 7, "amount" => "1"}
    end

    test "merge_outcome accepts a nil amount for max available", %{bypass: bypass} do
      respond(bypass, "/exchange", self(), %{"status" => "ok"})

      assert {:ok, _} = UserOutcome.merge_outcome(7, nil, private_key: @private_key)

      assert_receive {:request, request}
      assert request["action"]["mergeOutcome"] == %{"outcome" => 7, "amount" => nil}
    end

    test "merge_question sends the question variant", %{bypass: bypass} do
      respond(bypass, "/exchange", self(), %{"status" => "ok"})

      assert {:ok, _} = UserOutcome.merge_question(3, "2", private_key: @private_key)

      assert_receive {:request, request}
      assert request["action"]["mergeQuestion"] == %{"question" => 3, "amount" => "2"}
    end

    test "negate_outcome carries both question and outcome", %{bypass: bypass} do
      respond(bypass, "/exchange", self(), %{"status" => "ok"})

      assert {:ok, _} = UserOutcome.negate_outcome(3, 7, "1", private_key: @private_key)

      assert_receive {:request, request}

      assert request["action"]["negateOutcome"] == %{
               "question" => 3,
               "outcome" => 7,
               "amount" => "1"
             }
    end
  end

  describe "outcomeMetaUpdates subscription" do
    test "builds a bare request" do
      assert {:ok, %{type: "outcomeMetaUpdates"}} = OutcomeMetaUpdates.build_request(%{})
    end

    test "groups updates by kind and extracts settlements" do
      event = %{
        updates: [
          %{"outcomeCreated" => %{"outcome" => 7, "name" => "x"}},
          %{"outcomeSettled" => %{"outcome" => 7}},
          %{"questionSettled" => %{"question" => 3}},
          %{"questionUpdated" => %{"question" => 3}}
        ]
      }

      grouped = OutcomeMetaUpdates.group_updates(event)

      assert Map.keys(grouped) |> Enum.sort() ==
               ["outcomeCreated", "outcomeSettled", "questionSettled", "questionUpdated"]

      assert OutcomeMetaUpdates.settled_outcomes(event) == [7]
      assert OutcomeMetaUpdates.settled_questions(event) == [3]
    end

    test "tolerates an empty event" do
      assert OutcomeMetaUpdates.group_updates(%{updates: []}) == %{}
      assert OutcomeMetaUpdates.settled_outcomes(%{updates: []}) == []
    end
  end
end
