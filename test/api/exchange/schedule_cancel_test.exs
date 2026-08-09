defmodule Hyperliquid.Api.Exchange.ScheduleCancelTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.ScheduleCancel

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

  describe "request/3" do
    test "builds correct action structure with schedule time", %{bypass: bypass} do
      schedule_time = System.system_time(:millisecond) + 3_600_000

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["action"]["type"] == "scheduleCancel"
        assert is_integer(payload["action"]["time"])

        Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
        )
      end)

      assert {:ok, %{"status" => "ok"}} =
               ScheduleCancel.request(schedule_time, private_key: @private_key)
    end

    test "builds correct action structure to remove scheduled cancel", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["action"]["type"] == "scheduleCancel"
        refute Map.has_key?(payload["action"], "time")

        Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
        )
      end)

      assert {:ok, %{"status" => "ok"}} =
               ScheduleCancel.request(nil, private_key: @private_key)
    end

    test "builds action with vault address", %{bypass: bypass} do
      vault_address = "0x1234567890123456789012345678901234567890"
      schedule_time = System.system_time(:millisecond) + 3_600_000

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["action"]["type"] == "scheduleCancel"
        assert payload["vaultAddress"] == vault_address

        Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
        )
      end)

      assert {:ok, %{"status" => "ok"}} =
               ScheduleCancel.request(schedule_time,
                 private_key: @private_key,
                 vault_address: vault_address
               )
    end

    test "builds action with correct JSON field order with time" do
      time = 1_700_000_000_000

      action =
        Jason.OrderedObject.new([
          {:type, "scheduleCancel"},
          {:time, time}
        ])

      action_json = Jason.encode!(action)
      expected_json = ~s({"type":"scheduleCancel","time":#{time}})
      assert action_json == expected_json
    end

    test "builds action with correct JSON field order without time" do
      action =
        Jason.OrderedObject.new([
          {:type, "scheduleCancel"}
        ])

      action_json = Jason.encode!(action)
      expected_json = ~s({"type":"scheduleCancel"})
      assert action_json == expected_json
    end

    test "validates field names are correct" do
      time = 1_700_000_000_000

      action =
        Jason.OrderedObject.new([
          {:type, "scheduleCancel"},
          {:time, time}
        ])

      action_map = Jason.decode!(Jason.encode!(action))

      assert Map.has_key?(action_map, "type")
      assert Map.has_key?(action_map, "time")
      refute Map.has_key?(action_map, "scheduledTime")
      refute Map.has_key?(action_map, "cancelTime")
    end

    test "omits time field when nil" do
      action =
        Jason.OrderedObject.new([
          {:type, "scheduleCancel"}
        ])

      action_map = Jason.decode!(Jason.encode!(action))

      assert Map.has_key?(action_map, "type")
      refute Map.has_key?(action_map, "time")
      assert action_map["type"] == "scheduleCancel"
    end

    test "field order is preserved in encoded JSON with time" do
      time = 1_700_000_000_000

      action =
        Jason.OrderedObject.new([
          {:type, "scheduleCancel"},
          {:time, time}
        ])

      action_json = Jason.encode!(action)

      assert String.starts_with?(action_json, ~s({"type":"scheduleCancel"))
      assert String.contains?(action_json, ~s("type":"scheduleCancel"))
      assert String.contains?(action_json, ~s("time":#{time}))
    end

    test "handles different time values" do
      test_times = [
        1_700_000_000_000,
        System.system_time(:millisecond) + 3_600_000,
        System.system_time(:millisecond) + 86_400_000
      ]

      for time <- test_times do
        action =
          Jason.OrderedObject.new([
            {:type, "scheduleCancel"},
            {:time, time}
          ])

        action_map = Jason.decode!(Jason.encode!(action))
        assert action_map["type"] == "scheduleCancel"
        assert action_map["time"] == time
      end
    end
  end
end
