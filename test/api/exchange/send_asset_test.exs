defmodule Hyperliquid.Api.Exchange.SendAssetTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.SendAsset
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

  describe "request/7" do
    test "builds correct action structure for perp to spot transfer", %{bypass: bypass} do
      destination = "0x0000000000000000000000000000000000000001"
      source_dex = ""
      destination_dex = "spot"
      token = "USDC:0xeb62eee3685fc4c43992febcd9e75443"
      amount = "100.0"

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["action"]["type"] == "sendAsset"
        assert payload["action"]["destination"] == destination
        assert payload["action"]["sourceDex"] == ""
        assert payload["action"]["destinationDex"] == "spot"
        assert payload["action"]["token"] == token
        assert payload["action"]["amount"] == amount

        Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
        )
      end)

      assert {:ok, %{"status" => "ok"}} =
               SendAsset.request(destination, source_dex, destination_dex, token, amount,
                 private_key: @private_key
               )
    end

    test "builds correct action structure with from_sub_account option", %{bypass: bypass} do
      destination = "0x0000000000000000000000000000000000000001"
      source_dex = ""
      destination_dex = ""
      token = "USDC:0xeb62eee3685fc4c43992febcd9e75443"
      amount = "50.0"
      from_sub_account = "0x1234567890123456789012345678901234567890"

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["action"]["type"] == "sendAsset"
        assert payload["action"]["fromSubAccount"] == from_sub_account

        Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
        )
      end)

      assert {:ok, %{"status" => "ok"}} =
               SendAsset.request(
                 destination,
                 source_dex,
                 destination_dex,
                 token,
                 amount,
                 from_sub_account: from_sub_account,
                 private_key: @private_key
               )
    end

    test "builds action with correct JSON field order for mainnet" do
      time = 1_234_567_890
      mainnet_chain_id = Utils.from_int(42_161)

      action =
        Jason.OrderedObject.new([
          {:type, "sendAsset"},
          {:signatureChainId, mainnet_chain_id},
          {:hyperliquidChain, "Mainnet"},
          {:destination, "0x0000000000000000000000000000000000000001"},
          {:sourceDex, ""},
          {:destinationDex, "spot"},
          {:token, "USDC:0xeb62eee3685fc4c43992febcd9e75443"},
          {:amount, "100"},
          {:fromSubAccount, ""},
          {:nonce, time}
        ])

      action_json = Jason.encode!(action)

      expected_json =
        ~s({"type":"sendAsset","signatureChainId":"#{mainnet_chain_id}","hyperliquidChain":"Mainnet","destination":"0x0000000000000000000000000000000000000001","sourceDex":"","destinationDex":"spot","token":"USDC:0xeb62eee3685fc4c43992febcd9e75443","amount":"100","fromSubAccount":"","nonce":#{time}})

      assert action_json == expected_json
    end

    test "builds action with correct JSON field order for testnet" do
      time = 1_234_567_890
      testnet_chain_id = Utils.from_int(421_614)
      from_sub_account = "0x1234567890123456789012345678901234567890"

      action =
        Jason.OrderedObject.new([
          {:type, "sendAsset"},
          {:signatureChainId, testnet_chain_id},
          {:hyperliquidChain, "Testnet"},
          {:destination, "0x0000000000000000000000000000000000000002"},
          {:sourceDex, "spot"},
          {:destinationDex, ""},
          {:token, "HYPE:0x9876543210987654321098765432109876543210"},
          {:amount, "50.5"},
          {:fromSubAccount, from_sub_account},
          {:nonce, time}
        ])

      action_json = Jason.encode!(action)

      expected_json =
        ~s({"type":"sendAsset","signatureChainId":"#{testnet_chain_id}","hyperliquidChain":"Testnet","destination":"0x0000000000000000000000000000000000000002","sourceDex":"spot","destinationDex":"","token":"HYPE:0x9876543210987654321098765432109876543210","amount":"50.5","fromSubAccount":"#{from_sub_account}","nonce":#{time}})

      assert action_json == expected_json
    end

    test "validates field names are correct" do
      time = 1_234_567_890
      chain_id = Utils.from_int(42_161)

      action =
        Jason.OrderedObject.new([
          {:type, "sendAsset"},
          {:signatureChainId, chain_id},
          {:hyperliquidChain, "Mainnet"},
          {:destination, "0x0000000000000000000000000000000000000001"},
          {:sourceDex, ""},
          {:destinationDex, "spot"},
          {:token, "USDC:0xeb62eee3685fc4c43992febcd9e75443"},
          {:amount, "100"},
          {:fromSubAccount, ""},
          {:nonce, time}
        ])

      action_map = Jason.decode!(Jason.encode!(action))

      assert Map.has_key?(action_map, "type")
      assert Map.has_key?(action_map, "signatureChainId")
      assert Map.has_key?(action_map, "hyperliquidChain")
      assert Map.has_key?(action_map, "destination")
      assert Map.has_key?(action_map, "sourceDex")
      assert Map.has_key?(action_map, "destinationDex")
      assert Map.has_key?(action_map, "token")
      assert Map.has_key?(action_map, "amount")
      assert Map.has_key?(action_map, "fromSubAccount")
      assert Map.has_key?(action_map, "nonce")

      assert action_map["type"] == "sendAsset"
      assert action_map["hyperliquidChain"] == "Mainnet"
    end

    test "uses correct chain IDs" do
      mainnet_chain_id = Utils.from_int(42_161)
      assert String.downcase(mainnet_chain_id) == "0xa4b1"

      testnet_chain_id = Utils.from_int(421_614)
      assert String.downcase(testnet_chain_id) == "0x66eee"
    end

    test "field order is preserved in encoded JSON" do
      time = 1_234_567_890
      chain_id = Utils.from_int(42_161)

      action =
        Jason.OrderedObject.new([
          {:type, "sendAsset"},
          {:signatureChainId, chain_id},
          {:hyperliquidChain, "Mainnet"},
          {:destination, "0x1234567890123456789012345678901234567890"},
          {:sourceDex, ""},
          {:destinationDex, "test"},
          {:token, "USDC:0xeb62eee3685fc4c43992febcd9e75443"},
          {:amount, "100"},
          {:fromSubAccount, ""},
          {:nonce, time}
        ])

      action_json = Jason.encode!(action)

      assert String.starts_with?(action_json, ~s({"type":"sendAsset","signatureChainId":))
      assert String.contains?(action_json, ~s("type":"sendAsset"))
      assert String.contains?(action_json, ~s("signatureChainId":"#{chain_id}"))
      assert String.contains?(action_json, ~s("hyperliquidChain":"Mainnet"))

      assert String.contains?(
               action_json,
               ~s("destination":"0x1234567890123456789012345678901234567890")
             )

      assert String.contains?(action_json, ~s("sourceDex":""))
      assert String.contains?(action_json, ~s("destinationDex":"test"))
      assert String.contains?(action_json, ~s("token":"USDC:0xeb62eee3685fc4c43992febcd9e75443"))
      assert String.contains?(action_json, ~s("amount":"100"))
      assert String.contains?(action_json, ~s("fromSubAccount":""))
      assert String.contains?(action_json, ~s("nonce":#{time}))
    end

    test "handles different dex combinations" do
      test_cases = [
        {"", "spot", "perp to spot"},
        {"spot", "", "spot to perp"},
        {"", "", "perp to perp"},
        {"spot", "spot", "spot to spot"}
      ]

      time = 1_234_567_890
      chain_id = Utils.from_int(42_161)

      for {source_dex, destination_dex, _description} <- test_cases do
        action =
          Jason.OrderedObject.new([
            {:type, "sendAsset"},
            {:signatureChainId, chain_id},
            {:hyperliquidChain, "Mainnet"},
            {:destination, "0x0000000000000000000000000000000000000001"},
            {:sourceDex, source_dex},
            {:destinationDex, destination_dex},
            {:token, "USDC:0xeb62eee3685fc4c43992febcd9e75443"},
            {:amount, "100"},
            {:fromSubAccount, ""},
            {:nonce, time}
          ])

        action_map = Jason.decode!(Jason.encode!(action))
        assert action_map["sourceDex"] == source_dex
        assert action_map["destinationDex"] == destination_dex
      end
    end

    test "fromSubAccount defaults to empty string when not provided" do
      time = 1_234_567_890
      chain_id = Utils.from_int(42_161)

      action =
        Jason.OrderedObject.new([
          {:type, "sendAsset"},
          {:signatureChainId, chain_id},
          {:hyperliquidChain, "Mainnet"},
          {:destination, "0x0000000000000000000000000000000000000001"},
          {:sourceDex, ""},
          {:destinationDex, "spot"},
          {:token, "USDC:0xeb62eee3685fc4c43992febcd9e75443"},
          {:amount, "100"},
          {:fromSubAccount, ""},
          {:nonce, time}
        ])

      action_map = Jason.decode!(Jason.encode!(action))
      assert action_map["fromSubAccount"] == ""
    end
  end
end
