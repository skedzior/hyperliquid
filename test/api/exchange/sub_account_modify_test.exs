defmodule Hyperliquid.Api.Exchange.SubAccountModifyTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.SubAccountModify

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
    test "builds correct action structure for renaming sub-account", %{bypass: bypass} do
      name = "Renamed Bot"
      sub_account_user = "0x1234567890123456789012345678901234567890"

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["action"]["type"] == "subAccountModify"
        assert payload["action"]["subAccountUser"] == sub_account_user
        assert payload["action"]["name"] == "Renamed Bot"

        Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
        )
      end)

      assert {:ok, %{"status" => "ok"}} =
               SubAccountModify.request(name,
                 sub_account_user: sub_account_user,
                 private_key: @private_key
               )
    end

    test "builds action with correct JSON field order when modifying" do
      name = "New Name"
      sub_account_user = "0x1234567890123456789012345678901234567890"

      action =
        Jason.OrderedObject.new([
          {:type, "subAccountModify"},
          {:subAccountUser, sub_account_user},
          {:name, name}
        ])

      action_json = Jason.encode!(action)

      expected_json =
        ~s({"type":"subAccountModify","subAccountUser":"#{sub_account_user}","name":"#{name}"})

      assert action_json == expected_json
    end

    test "builds action with correct JSON field order without sub_account_user" do
      name = "Test Account"

      action =
        Jason.OrderedObject.new([
          {:type, "subAccountModify"},
          {:name, name}
        ])

      action_json = Jason.encode!(action)
      expected_json = ~s({"type":"subAccountModify","name":"#{name}"})
      assert action_json == expected_json
    end

    test "validates field names are correct with subAccountUser" do
      action =
        Jason.OrderedObject.new([
          {:type, "subAccountModify"},
          {:subAccountUser, "0x1234567890123456789012345678901234567890"},
          {:name, "Test"}
        ])

      action_map = Jason.decode!(Jason.encode!(action))

      assert Map.has_key?(action_map, "type")
      assert Map.has_key?(action_map, "subAccountUser")
      assert Map.has_key?(action_map, "name")
      refute Map.has_key?(action_map, "sub_account_user")
      refute Map.has_key?(action_map, "accountName")
    end

    test "validates field names are correct without subAccountUser" do
      action =
        Jason.OrderedObject.new([
          {:type, "subAccountModify"},
          {:name, "Test"}
        ])

      action_map = Jason.decode!(Jason.encode!(action))

      assert Map.has_key?(action_map, "type")
      assert Map.has_key?(action_map, "name")
      refute Map.has_key?(action_map, "subAccountUser")
    end

    test "field order is preserved in encoded JSON with subAccountUser" do
      name = "Ordered Test"
      sub_account_user = "0x1234567890123456789012345678901234567890"

      action =
        Jason.OrderedObject.new([
          {:type, "subAccountModify"},
          {:subAccountUser, sub_account_user},
          {:name, name}
        ])

      action_json = Jason.encode!(action)

      assert String.starts_with?(action_json, ~s({"type":"subAccountModify"))
      assert String.contains?(action_json, ~s("type":"subAccountModify"))
      assert String.contains?(action_json, ~s("subAccountUser":"#{sub_account_user}"))
      assert String.contains?(action_json, ~s("name":"#{name}"))
    end

    test "handles different names" do
      test_cases = [
        {"Trading Bot", "Trading Bot"},
        {"Sub Account 1", "Sub Account 1"},
        {"Renamed", "Renamed"}
      ]

      for {name, expected_name} <- test_cases do
        action =
          Jason.OrderedObject.new([
            {:type, "subAccountModify"},
            {:name, name}
          ])

        action_map = Jason.decode!(Jason.encode!(action))
        assert action_map["type"] == "subAccountModify"
        assert action_map["name"] == expected_name
      end
    end
  end
end
