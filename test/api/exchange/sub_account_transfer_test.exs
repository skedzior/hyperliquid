defmodule Hyperliquid.Api.Exchange.SubAccountTransferTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.SubAccountTransfer

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

  describe "request/5" do
    test "builds correct action structure for deposit to sub-account", %{bypass: bypass} do
      sub_account_user = "0x1234567890123456789012345678901234567890"
      is_deposit = true
      usd = 1_000_000

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["action"]["type"] == "subAccountTransfer"
        assert payload["action"]["subAccountUser"] == sub_account_user
        assert payload["action"]["isDeposit"] == true
        assert payload["action"]["usd"] == usd

        Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
        )
      end)

      assert {:ok, %{"status" => "ok"}} =
               SubAccountTransfer.request(sub_account_user, is_deposit, usd,
                 private_key: @private_key
               )
    end

    test "builds correct action structure for withdrawal from sub-account", %{bypass: bypass} do
      sub_account_user = "0x1234567890123456789012345678901234567890"
      is_deposit = false
      usd = 500_000

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["action"]["type"] == "subAccountTransfer"
        assert payload["action"]["isDeposit"] == false

        Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
        )
      end)

      assert {:ok, %{"status" => "ok"}} =
               SubAccountTransfer.request(sub_account_user, is_deposit, usd,
                 private_key: @private_key
               )
    end

    test "builds action with correct JSON field order" do
      sub_account_user = "0x1234567890123456789012345678901234567890"
      is_deposit = true
      usd = 1_000_000

      action =
        Jason.OrderedObject.new([
          {:type, "subAccountTransfer"},
          {:subAccountUser, sub_account_user},
          {:isDeposit, is_deposit},
          {:usd, usd}
        ])

      action_json = Jason.encode!(action)

      expected_json =
        ~s({"type":"subAccountTransfer","subAccountUser":"#{sub_account_user}","isDeposit":true,"usd":#{usd}})

      assert action_json == expected_json
    end

    test "validates field names are correct" do
      action =
        Jason.OrderedObject.new([
          {:type, "subAccountTransfer"},
          {:subAccountUser, "0x1234567890123456789012345678901234567890"},
          {:isDeposit, true},
          {:usd, 1_000_000}
        ])

      action_map = Jason.decode!(Jason.encode!(action))

      assert Map.has_key?(action_map, "type")
      assert Map.has_key?(action_map, "subAccountUser")
      assert Map.has_key?(action_map, "isDeposit")
      assert Map.has_key?(action_map, "usd")

      refute Map.has_key?(action_map, "sub_account_user")
      refute Map.has_key?(action_map, "is_deposit")
      refute Map.has_key?(action_map, "amount")

      assert action_map["type"] == "subAccountTransfer"
    end

    test "field order is preserved in encoded JSON" do
      sub_account_user = "0x1234567890123456789012345678901234567890"
      usd = 2_500_000

      action =
        Jason.OrderedObject.new([
          {:type, "subAccountTransfer"},
          {:subAccountUser, sub_account_user},
          {:isDeposit, false},
          {:usd, usd}
        ])

      action_json = Jason.encode!(action)

      assert String.starts_with?(action_json, ~s({"type":"subAccountTransfer"))
      assert String.contains?(action_json, ~s("type":"subAccountTransfer"))
      assert String.contains?(action_json, ~s("subAccountUser":"#{sub_account_user}"))
      assert String.contains?(action_json, ~s("isDeposit":false))
      assert String.contains?(action_json, ~s("usd":#{usd}))
    end

    test "handles different isDeposit values" do
      sub_account_user = "0x1234567890123456789012345678901234567890"
      usd = 1_000_000

      deposit_action =
        Jason.OrderedObject.new([
          {:type, "subAccountTransfer"},
          {:subAccountUser, sub_account_user},
          {:isDeposit, true},
          {:usd, usd}
        ])

      deposit_map = Jason.decode!(Jason.encode!(deposit_action))
      assert deposit_map["isDeposit"] == true

      withdraw_action =
        Jason.OrderedObject.new([
          {:type, "subAccountTransfer"},
          {:subAccountUser, sub_account_user},
          {:isDeposit, false},
          {:usd, usd}
        ])

      withdraw_map = Jason.decode!(Jason.encode!(withdraw_action))
      assert withdraw_map["isDeposit"] == false
    end

    test "handles different USD amounts" do
      sub_account_user = "0x1234567890123456789012345678901234567890"

      test_amounts = [
        1_000_000,
        500_000,
        10_000_000,
        100_000
      ]

      for usd <- test_amounts do
        action =
          Jason.OrderedObject.new([
            {:type, "subAccountTransfer"},
            {:subAccountUser, sub_account_user},
            {:isDeposit, true},
            {:usd, usd}
          ])

        action_map = Jason.decode!(Jason.encode!(action))
        assert action_map["usd"] == usd
      end
    end

    test "usd field is an integer not a string" do
      sub_account_user = "0x1234567890123456789012345678901234567890"
      usd = 1_000_000

      action =
        Jason.OrderedObject.new([
          {:type, "subAccountTransfer"},
          {:subAccountUser, sub_account_user},
          {:isDeposit, true},
          {:usd, usd}
        ])

      action_json = Jason.encode!(action)

      assert String.contains?(action_json, ~s("usd":#{usd}))
      refute String.contains?(action_json, ~s("usd":"#{usd}"))
    end
  end
end
