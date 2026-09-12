defmodule Hyperliquid.Api.Exchange.OutcomeActionsTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.{ActivateOutcomeDeployer, UserOutcome}

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
    action_json = extract_action(body)
    action_json
  end

  describe "activateOutcomeDeployer" do
    # Official HIP-4 page shape: activate carries a venueName; deactivate is null.
    # (nktkas v0.33.3 still emits the flatter {"isDeactivate": bool} form.)
    test "activate emits a venueName object", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          ActivateOutcomeDeployer.activate("abcd", private_key: @private_key)
        end)

      assert raw == ~s({"type":"activateOutcomeDeployer","activate":{"venueName":"abcd"}})
    end

    test "deactivate emits a null", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          ActivateOutcomeDeployer.deactivate(private_key: @private_key)
        end)

      assert raw == ~s({"type":"activateOutcomeDeployer","deactivate":null})
    end

    test "rejects an invalid venue name" do
      assert_raise ArgumentError, fn ->
        ActivateOutcomeDeployer.activate("TOOLONG", private_key: @private_key)
      end
    end
  end

  describe "userOutcome" do
    test "splitOutcome", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          UserOutcome.split_outcome(95, "10.5", private_key: @private_key)
        end)

      assert raw == ~s({"type":"userOutcome","splitOutcome":{"outcome":95,"amount":"10.5"}})
    end

    test "mergeOutcome with an amount", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          UserOutcome.merge_outcome(95, "1", private_key: @private_key)
        end)

      assert raw == ~s({"type":"userOutcome","mergeOutcome":{"outcome":95,"amount":"1"}})
    end

    test "mergeOutcome with a nil amount means 'everything'", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          UserOutcome.merge_outcome(95, nil, private_key: @private_key)
        end)

      assert raw == ~s({"type":"userOutcome","mergeOutcome":{"outcome":95,"amount":null}})
    end

    test "mergeQuestion", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          UserOutcome.merge_question(3, nil, private_key: @private_key)
        end)

      assert raw == ~s({"type":"userOutcome","mergeQuestion":{"question":3,"amount":null}})
    end

    test "negateOutcome", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          UserOutcome.negate_outcome(3, 95, "2", private_key: @private_key)
        end)

      assert raw ==
               ~s({"type":"userOutcome","negateOutcome":{"question":3,"outcome":95,"amount":"2"}})
    end

    test "exactly one variant key is present per action", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          UserOutcome.split_outcome(1, "1", private_key: @private_key)
        end)

      keys = raw |> Jason.decode!() |> Map.keys() |> Enum.sort()
      assert keys == ["splitOutcome", "type"]
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
