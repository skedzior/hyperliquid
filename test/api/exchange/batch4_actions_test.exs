defmodule Hyperliquid.Api.Exchange.Batch4ActionsTest do
  @moduledoc """
  Coverage for the agent transfer, AQAV2, EVM finalization, HIP-3 liquidator,
  staking-link and isolated-margin actions.
  """
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.{
    AgentSendAsset,
    AuthorizeAqav2Role,
    FinalizeEvmContract,
    Hip3LiquidatorTransfer,
    StakingLinkDisableTradingUser,
    TopUpIsolatedOnlyMargin
  }

  @private_key "0x822e9959e022b78423eb653a62ea0020cd283e71a2a8133a6ff2aeffaf373cff"
  @address "0x1234567890123456789012345678901234567890"

  setup do
    bypass = Bypass.open()
    prev_url = Application.get_env(:hyperliquid, :http_url)
    Application.put_env(:hyperliquid, :http_url, "http://localhost:#{bypass.port}")

    on_exit(fn ->
      if prev_url,
        do: Application.put_env(:hyperliquid, :http_url, prev_url),
        else: Application.delete_env(:hyperliquid, :http_url)
    end)

    test_pid = self()

    # stub rather than expect: the validation-only tests never reach the network.
    Bypass.stub(bypass, "POST", "/exchange", fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:raw, raw})

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"status" => "ok"}))
    end)

    {:ok, bypass: bypass}
  end

  defp action_from_body do
    assert_receive {:raw, raw}
    {raw, Jason.decode!(raw)["action"]}
  end

  describe "agentSendAsset" do
    test "sends all transfer fields in canonical order" do
      assert {:ok, _} =
               AgentSendAsset.request(@address, "", "spot", "USDC", "100",
                 private_key: @private_key
               )

      {raw, action} = action_from_body()

      assert action["type"] == "agentSendAsset"
      assert action["destination"] == @address
      assert action["sourceDex"] == ""
      assert action["destinationDex"] == "spot"
      assert action["token"] == "USDC"
      assert action["amount"] == "100"
      assert action["fromSubAccount"] == ""
      assert is_integer(action["nonce"])

      assert raw =~
               ~s("type":"agentSendAsset","destination":"#{@address}","sourceDex":"","destinationDex":"spot","token":"USDC","amount":"100","fromSubAccount":"","nonce":)
    end

    test "honours a from_sub_account option" do
      assert {:ok, _} =
               AgentSendAsset.request(@address, "", "spot", "USDC", "1",
                 private_key: @private_key,
                 from_sub_account: @address
               )

      {_raw, action} = action_from_body()
      assert action["fromSubAccount"] == @address
    end
  end

  describe "authorizeAqav2Role" do
    test "accepts atom roles" do
      assert {:ok, _} = AuthorizeAqav2Role.request(42, :treasury, private_key: @private_key)

      {raw, action} = action_from_body()
      assert action["token"] == 42
      assert action["role"] == "treasury"
      assert raw =~ ~s("type":"authorizeAqav2Role","token":42,"role":"treasury")
    end

    test "accepts string roles" do
      assert {:ok, _} = AuthorizeAqav2Role.request(1, "technical", private_key: @private_key)
      {_raw, action} = action_from_body()
      assert action["role"] == "technical"
    end

    test "rejects unknown roles" do
      assert_raise ArgumentError, ~r/:technical or :treasury/, fn ->
        AuthorizeAqav2Role.request(1, :admin, private_key: @private_key)
      end

      assert_raise ArgumentError, ~r/:technical or :treasury/, fn ->
        AuthorizeAqav2Role.request(1, "admin", private_key: @private_key)
      end
    end

    test "roles/0 lists both roles" do
      assert Enum.sort(AuthorizeAqav2Role.roles()) == ["technical", "treasury"]
    end
  end

  describe "finalizeEvmContract" do
    test "create variant nests the deploy nonce" do
      assert {:ok, _} = FinalizeEvmContract.finalize_with_create(42, 7, private_key: @private_key)

      {raw, action} = action_from_body()
      assert action["token"] == 42
      assert action["input"] == %{"create" => %{"nonce" => 7}}
      assert raw =~ ~s("type":"finalizeEvmContract","token":42,"input":{"create":{"nonce":7}})
    end

    test "first storage slot variant is a bare string" do
      assert {:ok, _} =
               FinalizeEvmContract.finalize_with_first_storage_slot(42, private_key: @private_key)

      {_raw, action} = action_from_body()
      assert action["input"] == "firstStorageSlot"
    end

    test "custom storage slot variant is a bare string" do
      assert {:ok, _} =
               FinalizeEvmContract.finalize_with_custom_storage_slot(42,
                 private_key: @private_key
               )

      {_raw, action} = action_from_body()
      assert action["input"] == "customStorageSlot"
    end
  end

  describe "hip3LiquidatorTransfer" do
    test "deposit sets isDeposit true" do
      assert {:ok, _} = Hip3LiquidatorTransfer.deposit("test", 1000, private_key: @private_key)

      {raw, action} = action_from_body()
      assert action["dex"] == "test"
      assert action["ntl"] == 1000
      assert action["isDeposit"] == true
      assert raw =~ ~s("type":"hip3LiquidatorTransfer","dex":"test","ntl":1000,"isDeposit":true)
    end

    test "withdraw sets isDeposit false" do
      assert {:ok, _} = Hip3LiquidatorTransfer.withdraw("test", 500, private_key: @private_key)

      {_raw, action} = action_from_body()
      assert action["isDeposit"] == false
    end

    test "rejects negative notional" do
      assert_raise ArgumentError, ~r/ntl must be non-negative/, fn ->
        Hip3LiquidatorTransfer.deposit("test", -1, private_key: @private_key)
      end
    end
  end

  describe "topUpIsolatedOnlyMargin" do
    test "sends asset and leverage" do
      assert {:ok, _} = TopUpIsolatedOnlyMargin.request(3, "5", private_key: @private_key)

      {raw, action} = action_from_body()
      assert action["asset"] == 3
      assert action["leverage"] == "5"
      assert raw =~ ~s("type":"topUpIsolatedOnlyMargin","asset":3,"leverage":"5")
    end

    test "converts numeric leverage to a decimal string" do
      assert {:ok, _} = TopUpIsolatedOnlyMargin.request(3, 5, private_key: @private_key)
      {_raw, action} = action_from_body()
      assert action["leverage"] == "5"
    end
  end

  describe "stakingLinkDisableTradingUser" do
    test "sends a user-signed action with chain metadata" do
      assert {:ok, _} =
               StakingLinkDisableTradingUser.request(@address, private_key: @private_key)

      {_raw, action} = action_from_body()

      assert action["type"] == "stakingLinkDisableTradingUser"
      assert action["tradingUser"] == @address
      assert action["hyperliquidChain"] in ["Mainnet", "Testnet"]
      assert action["signatureChainId"] == Hyperliquid.Config.signature_chain_id_hex()
      assert is_integer(action["nonce"])
    end

    test "signature is a well-formed ECDSA triple" do
      assert {:ok, _} =
               StakingLinkDisableTradingUser.request(@address, private_key: @private_key)

      assert_receive {:raw, raw}
      signature = Jason.decode!(raw)["signature"]

      assert String.starts_with?(signature["r"], "0x")
      assert String.starts_with?(signature["s"], "0x")
      assert signature["v"] in [27, 28]
    end
  end
end
