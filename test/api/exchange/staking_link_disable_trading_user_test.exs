defmodule Hyperliquid.Api.Exchange.StakingLinkDisableTradingUserTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.StakingLinkDisableTradingUser, as: Action

  @private_key "0000000000000000000000000000000000000000000000000000000000000001"
  @trading_user "0x0000000000000000000000000000000000000002"

  setup do
    bypass = Bypass.open()
    Application.put_env(:hyperliquid, :http_url, "http://localhost:#{bypass.port}")

    Bypass.stub(bypass, "POST", "/info", fn conn ->
      Plug.Conn.put_resp_header(conn, "content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{}))
    end)

    {:ok, bypass: bypass}
  end

  describe "EIP-712 typed data" do
    test "primary type matches the TS SDK" do
      assert Action.primary_type() == "HyperliquidTransaction:StakingLinkDisableTradingUser"
    end

    test "type table is hyperliquidChain/string, tradingUser/address, nonce/uint64" do
      types = Action.eip712_types()

      assert types[Action.primary_type()] == [
               %{name: "hyperliquidChain", type: "string"},
               %{name: "tradingUser", type: "address"},
               %{name: "nonce", type: "uint64"}
             ]

      assert types["EIP712Domain"] == [
               %{name: "name", type: "string"},
               %{name: "version", type: "string"},
               %{name: "chainId", type: "uint256"},
               %{name: "verifyingContract", type: "address"}
             ]
    end
  end

  describe "action shape" do
    test "key order: type, signatureChainId, hyperliquidChain, tradingUser, nonce" do
      nonce = 1_234_567_890
      chain_id = Hyperliquid.Config.signature_chain_id_hex()

      assert Jason.encode!(Action.build_action(@trading_user, nonce, true)) ==
               ~s({"type":"stakingLinkDisableTradingUser","signatureChainId":"#{chain_id}",) <>
                 ~s("hyperliquidChain":"Mainnet","tradingUser":"#{@trading_user}","nonce":#{nonce}})
    end

    test "testnet flips hyperliquidChain but keeps the configured signatureChainId" do
      action = Jason.decode!(Jason.encode!(Action.build_action(@trading_user, 1, false)))

      assert action["hyperliquidChain"] == "Testnet"

      assert String.downcase(action["signatureChainId"]) ==
               Hyperliquid.Config.signature_chain_id_hex()
    end
  end

  describe "request/2" do
    test "posts the user-signed action", %{bypass: bypass} do
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

      assert {:ok, %{"status" => "ok"}} =
               Action.request(@trading_user, private_key: @private_key)

      assert_receive {:body, body}
      payload = Jason.decode!(body)

      assert payload["action"]["type"] == "stakingLinkDisableTradingUser"
      assert payload["action"]["tradingUser"] == @trading_user
      assert payload["action"]["nonce"] == payload["nonce"]
      assert %{"r" => _, "s" => _, "v" => _} = payload["signature"]
    end
  end
end
