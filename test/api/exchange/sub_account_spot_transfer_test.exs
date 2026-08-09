defmodule Hyperliquid.Api.Exchange.SubAccountSpotTransferTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.SubAccountSpotTransfer
  alias Hyperliquid.Utils

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

  describe "request/6" do
    test "builds correct action structure for deposit to sub-account", %{bypass: bypass} do
      sub_account_user = "0x1234567890123456789012345678901234567890"
      is_deposit = true
      token = "USDC:0xeb62eee3685fc4c43992febcd9e75443"
      amount = "100.0"

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["action"]["type"] == "subAccountSpotTransfer"
        assert payload["action"]["subAccountUser"] == sub_account_user
        assert payload["action"]["isDeposit"] == true
        assert payload["action"]["token"] == token

        Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
        )
      end)

      assert {:ok, %{"status" => "ok"}} =
               SubAccountSpotTransfer.request(sub_account_user, is_deposit, token, amount,
                 private_key: @private_key
               )
    end

    test "builds correct action structure for withdrawal from sub-account", %{bypass: bypass} do
      sub_account_user = "0x1234567890123456789012345678901234567890"
      is_deposit = false
      token = "HYPE:0x9876543210987654321098765432109876543210"
      amount = "50.5"

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["action"]["type"] == "subAccountSpotTransfer"
        assert payload["action"]["isDeposit"] == false

        Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
        )
      end)

      assert {:ok, %{"status" => "ok"}} =
               SubAccountSpotTransfer.request(sub_account_user, is_deposit, token, amount,
                 private_key: @private_key
               )
    end

    test "builds action with correct JSON field order" do
      sub_account_user = "0x1234567890123456789012345678901234567890"
      is_deposit = true
      token = "USDC:0xeb62eee3685fc4c43992febcd9e75443"
      amount = "100"

      action =
        Jason.OrderedObject.new([
          {:type, "subAccountSpotTransfer"},
          {:subAccountUser, sub_account_user},
          {:isDeposit, is_deposit},
          {:token, token},
          {:amount, amount}
        ])

      action_json = Jason.encode!(action)

      expected_json =
        ~s({"type":"subAccountSpotTransfer","subAccountUser":"#{sub_account_user}","isDeposit":true,"token":"#{token}","amount":"#{amount}"})

      assert action_json == expected_json
    end

    test "validates field names are correct" do
      action =
        Jason.OrderedObject.new([
          {:type, "subAccountSpotTransfer"},
          {:subAccountUser, "0x1234567890123456789012345678901234567890"},
          {:isDeposit, true},
          {:token, "USDC:0xeb62eee3685fc4c43992febcd9e75443"},
          {:amount, "100"}
        ])

      action_map = Jason.decode!(Jason.encode!(action))

      assert Map.has_key?(action_map, "type")
      assert Map.has_key?(action_map, "subAccountUser")
      assert Map.has_key?(action_map, "isDeposit")
      assert Map.has_key?(action_map, "token")
      assert Map.has_key?(action_map, "amount")

      refute Map.has_key?(action_map, "sub_account_user")
      refute Map.has_key?(action_map, "is_deposit")

      assert action_map["type"] == "subAccountSpotTransfer"
    end

    test "field order is preserved in encoded JSON" do
      sub_account_user = "0x1234567890123456789012345678901234567890"
      token = "USDC:0xeb62eee3685fc4c43992febcd9e75443"

      action =
        Jason.OrderedObject.new([
          {:type, "subAccountSpotTransfer"},
          {:subAccountUser, sub_account_user},
          {:isDeposit, false},
          {:token, token},
          {:amount, "50.5"}
        ])

      action_json = Jason.encode!(action)

      assert String.starts_with?(action_json, ~s({"type":"subAccountSpotTransfer"))
      assert String.contains?(action_json, ~s("type":"subAccountSpotTransfer"))
      assert String.contains?(action_json, ~s("subAccountUser":"#{sub_account_user}"))
      assert String.contains?(action_json, ~s("isDeposit":false))
      assert String.contains?(action_json, ~s("token":"#{token}"))
      assert String.contains?(action_json, ~s("amount":"50.5"))
    end

    test "handles different isDeposit values" do
      sub_account_user = "0x1234567890123456789012345678901234567890"
      token = "USDC:0xeb62eee3685fc4c43992febcd9e75443"

      deposit_action =
        Jason.OrderedObject.new([
          {:type, "subAccountSpotTransfer"},
          {:subAccountUser, sub_account_user},
          {:isDeposit, true},
          {:token, token},
          {:amount, "100"}
        ])

      deposit_map = Jason.decode!(Jason.encode!(deposit_action))
      assert deposit_map["isDeposit"] == true

      withdraw_action =
        Jason.OrderedObject.new([
          {:type, "subAccountSpotTransfer"},
          {:subAccountUser, sub_account_user},
          {:isDeposit, false},
          {:token, token},
          {:amount, "50"}
        ])

      withdraw_map = Jason.decode!(Jason.encode!(withdraw_action))
      assert withdraw_map["isDeposit"] == false
    end

    test "formats amount correctly using float_to_string" do
      test_cases = [
        {"100.0", "100"},
        {"50.5", "50.5"},
        {"0.123", "0.123"},
        {"1000.456789", "1000.456789"}
      ]

      for {input, expected} <- test_cases do
        result = Utils.float_to_string(input)
        assert result == expected
      end
    end

    test "handles different tokens" do
      sub_account_user = "0x1234567890123456789012345678901234567890"

      test_tokens = [
        "USDC:0xeb62eee3685fc4c43992febcd9e75443",
        "HYPE:0x1234567890123456789012345678901234567890",
        "TOKEN:0xabcdefabcdefabcdefabcdefabcdefabcdef"
      ]

      for token <- test_tokens do
        action =
          Jason.OrderedObject.new([
            {:type, "subAccountSpotTransfer"},
            {:subAccountUser, sub_account_user},
            {:isDeposit, true},
            {:token, token},
            {:amount, "100"}
          ])

        action_map = Jason.decode!(Jason.encode!(action))
        assert action_map["token"] == token
      end
    end
  end
end
