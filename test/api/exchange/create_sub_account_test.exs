defmodule Hyperliquid.Api.Exchange.CreateSubAccountTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.CreateSubAccount

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
    test "builds correct action structure for basic sub-account creation", %{bypass: bypass} do
      name = "Trading Bot"

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["action"]["type"] == "createSubAccount"
        assert payload["action"]["name"] == "Trading Bot"

        Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
        )
      end)

      assert {:ok, %{"status" => "ok"}} =
               CreateSubAccount.request(name, private_key: @private_key)
    end

    test "builds action with correct JSON field order" do
      name = "Test Account"

      action =
        Jason.OrderedObject.new([
          {:type, "createSubAccount"},
          {:name, name}
        ])

      action_json = Jason.encode!(action)
      expected_json = ~s({"type":"createSubAccount","name":"Test Account"})
      assert action_json == expected_json
    end

    test "builds action with different names" do
      test_names = [
        "Trading Bot",
        "Sub Account 1",
        "Test",
        "My Account 123"
      ]

      for name <- test_names do
        action =
          Jason.OrderedObject.new([
            {:type, "createSubAccount"},
            {:name, name}
          ])

        action_map = Jason.decode!(Jason.encode!(action))
        assert action_map["type"] == "createSubAccount"
        assert action_map["name"] == name
      end
    end

    test "validates field names are correct" do
      action =
        Jason.OrderedObject.new([
          {:type, "createSubAccount"},
          {:name, "Test"}
        ])

      action_map = Jason.decode!(Jason.encode!(action))

      assert Map.has_key?(action_map, "type")
      assert Map.has_key?(action_map, "name")
      refute Map.has_key?(action_map, "accountName")
      refute Map.has_key?(action_map, "subAccountName")
    end

    test "field order is preserved in encoded JSON" do
      name = "Ordered Test"

      action =
        Jason.OrderedObject.new([
          {:type, "createSubAccount"},
          {:name, name}
        ])

      action_json = Jason.encode!(action)

      assert String.starts_with?(action_json, ~s({"type":"createSubAccount"))
      assert String.contains?(action_json, ~s("type":"createSubAccount"))
      assert String.contains?(action_json, ~s("name":"#{name}"))
    end
  end
end
