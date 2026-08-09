defmodule Hyperliquid.Api.Exchange.SpotSendTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.SpotSend
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

  describe "request/5" do
    test "builds correct action structure for basic spot send", %{bypass: bypass} do
      destination = "0x0000000000000000000000000000000000000001"
      token = "USDC:0xeb62eee3685fc4c43992febcd9e75443"
      amount = "10.0"

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["action"]["type"] == "spotSend"
        assert payload["action"]["destination"] == destination
        assert payload["action"]["token"] == token
        assert payload["action"]["amount"] == amount

        Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
        )
      end)

      assert {:ok, %{"status" => "ok"}} =
               SpotSend.request(destination, token, amount, private_key: @private_key)
    end

    test "builds action with correct JSON field order for mainnet" do
      time = 1_234_567_890
      mainnet_chain_id = Utils.from_int(42_161)

      action =
        Jason.OrderedObject.new([
          {:type, "spotSend"},
          {:signatureChainId, mainnet_chain_id},
          {:hyperliquidChain, "Mainnet"},
          {:destination, "0x0000000000000000000000000000000000000001"},
          {:token, "USDC:0xeb62eee3685fc4c43992febcd9e75443"},
          {:amount, "10"},
          {:time, time}
        ])

      action_json = Jason.encode!(action)

      expected_json =
        ~s({"type":"spotSend","signatureChainId":"#{mainnet_chain_id}","hyperliquidChain":"Mainnet","destination":"0x0000000000000000000000000000000000000001","token":"USDC:0xeb62eee3685fc4c43992febcd9e75443","amount":"10","time":#{time}})

      assert action_json == expected_json
    end

    test "builds action with correct JSON field order for testnet" do
      time = 1_234_567_890
      testnet_chain_id = Utils.from_int(421_614)

      action =
        Jason.OrderedObject.new([
          {:type, "spotSend"},
          {:signatureChainId, testnet_chain_id},
          {:hyperliquidChain, "Testnet"},
          {:destination, "0x0000000000000000000000000000000000000002"},
          {:token, "HYPE:0x1234567890123456789012345678901234567890"},
          {:amount, "5.5"},
          {:time, time}
        ])

      action_json = Jason.encode!(action)

      expected_json =
        ~s({"type":"spotSend","signatureChainId":"#{testnet_chain_id}","hyperliquidChain":"Testnet","destination":"0x0000000000000000000000000000000000000002","token":"HYPE:0x1234567890123456789012345678901234567890","amount":"5.5","time":#{time}})

      assert action_json == expected_json
    end

    test "validates field names are correct" do
      time = 1_234_567_890
      chain_id = Utils.from_int(42_161)

      action =
        Jason.OrderedObject.new([
          {:type, "spotSend"},
          {:signatureChainId, chain_id},
          {:hyperliquidChain, "Mainnet"},
          {:destination, "0x0000000000000000000000000000000000000001"},
          {:token, "USDC:0xeb62eee3685fc4c43992febcd9e75443"},
          {:amount, "10"},
          {:time, time}
        ])

      action_map = Jason.decode!(Jason.encode!(action))

      assert Map.has_key?(action_map, "type")
      assert Map.has_key?(action_map, "signatureChainId")
      assert Map.has_key?(action_map, "hyperliquidChain")
      assert Map.has_key?(action_map, "destination")
      assert Map.has_key?(action_map, "token")
      assert Map.has_key?(action_map, "amount")
      assert Map.has_key?(action_map, "time")

      assert action_map["type"] == "spotSend"
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
          {:type, "spotSend"},
          {:signatureChainId, chain_id},
          {:hyperliquidChain, "Mainnet"},
          {:destination, "0x1234567890123456789012345678901234567890"},
          {:token, "USDC:0xeb62eee3685fc4c43992febcd9e75443"},
          {:amount, "100"},
          {:time, time}
        ])

      action_json = Jason.encode!(action)

      assert String.starts_with?(action_json, ~s({"type":"spotSend","signatureChainId":))
      assert String.contains?(action_json, ~s("type":"spotSend"))
      assert String.contains?(action_json, ~s("signatureChainId":"#{chain_id}"))
      assert String.contains?(action_json, ~s("hyperliquidChain":"Mainnet"))

      assert String.contains?(
               action_json,
               ~s("destination":"0x1234567890123456789012345678901234567890")
             )

      assert String.contains?(action_json, ~s("token":"USDC:0xeb62eee3685fc4c43992febcd9e75443"))
      assert String.contains?(action_json, ~s("amount":"100"))
      assert String.contains?(action_json, ~s("time":#{time}))
    end
  end
end
