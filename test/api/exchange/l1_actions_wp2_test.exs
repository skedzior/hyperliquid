defmodule Hyperliquid.Api.Exchange.L1ActionsWp2Test do
  @moduledoc """
  Wire-shape tests for the plain L1 exchange actions added alongside the HIP-4 work.
  Shapes are cross-checked against @nktkas/hyperliquid v0.33.3 and the official
  exchange-endpoint page.
  """

  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.{
    AgentSendAsset,
    AuthorizeAqav2Role,
    FinalizeEvmContract,
    GossipPriorityBid,
    Hip3LiquidatorTransfer,
    ReserveRequestWeight,
    TopUpIsolatedOnlyMargin
  }

  @private_key "0000000000000000000000000000000000000000000000000000000000000001"
  @address "0x0000000000000000000000000000000000000001"

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

  describe "agentSendAsset" do
    test "L1 shape: no signatureChainId/hyperliquidChain, inner nonce present", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          AgentSendAsset.request(@address, "", "spot", "USDC:0xabc", "100.0",
            private_key: @private_key
          )
        end)

      action = Jason.decode!(raw)

      refute Map.has_key?(action, "signatureChainId")
      refute Map.has_key?(action, "hyperliquidChain")
      assert action["type"] == "agentSendAsset"
      assert action["fromSubAccount"] == ""
      assert is_integer(action["nonce"])

      assert String.starts_with?(
               raw,
               ~s({"type":"agentSendAsset","destination":"#{@address}","sourceDex":"",) <>
                 ~s("destinationDex":"spot","token":"USDC:0xabc","amount":"100.0",) <>
                 ~s("fromSubAccount":"","nonce":)
             )
    end

    test "from_sub_account option is honoured", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          AgentSendAsset.request(@address, "", "spot", "USDC:0xabc", "1",
            from_sub_account: @address,
            private_key: @private_key
          )
        end)

      assert Jason.decode!(raw)["fromSubAccount"] == @address
    end
  end

  describe "authorizeAqav2Role" do
    test "emits token and role in order", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          AuthorizeAqav2Role.request(42, "treasury", private_key: @private_key)
        end)

      assert raw == ~s({"type":"authorizeAqav2Role","token":42,"role":"treasury"})
    end

    test "rejects an unknown role" do
      assert_raise ArgumentError, fn ->
        AuthorizeAqav2Role.request(42, "admin", private_key: @private_key)
      end
    end
  end

  describe "finalizeEvmContract" do
    test "create variant nests a nonce", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          FinalizeEvmContract.request(42, {:create, 7}, private_key: @private_key)
        end)

      assert raw ==
               ~s({"type":"finalizeEvmContract","token":42,"input":{"create":{"nonce":7}}})
    end

    test "storage-slot variants are bare strings", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          FinalizeEvmContract.request(42, :first_storage_slot, private_key: @private_key)
        end)

      assert raw == ~s({"type":"finalizeEvmContract","token":42,"input":"firstStorageSlot"})

      raw2 =
        capture_action(bypass, fn ->
          FinalizeEvmContract.request(42, :custom_storage_slot, private_key: @private_key)
        end)

      assert raw2 == ~s({"type":"finalizeEvmContract","token":42,"input":"customStorageSlot"})
    end

    test "rejects an unknown input" do
      assert_raise ArgumentError, fn ->
        FinalizeEvmContract.request(42, :nope, private_key: @private_key)
      end
    end
  end

  describe "gossipPriorityBid" do
    test "emits slotId, ip, maxGas", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          GossipPriorityBid.request(1, "1.2.3.4", 5000, private_key: @private_key)
        end)

      assert raw ==
               ~s({"type":"gossipPriorityBid","slotId":1,"ip":"1.2.3.4","maxGas":5000})
    end

    test "rejects a slot id above 1" do
      assert_raise ArgumentError, fn ->
        GossipPriorityBid.request(2, "1.2.3.4", 1, private_key: @private_key)
      end
    end
  end

  describe "hip3LiquidatorTransfer" do
    test "emits dex, ntl, isDeposit", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          Hip3LiquidatorTransfer.request("mydex", 1_000_000, true, private_key: @private_key)
        end)

      assert raw ==
               ~s({"type":"hip3LiquidatorTransfer","dex":"mydex","ntl":1000000,"isDeposit":true})
    end
  end

  describe "topUpIsolatedOnlyMargin" do
    test "emits asset and leverage, and supports vault_address", %{bypass: bypass} do
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

      assert {:ok, _} =
               TopUpIsolatedOnlyMargin.request(0, "3",
                 vault_address: @address,
                 private_key: @private_key
               )

      assert_receive {:body, body}
      raw = extract_action(body)

      assert raw == ~s({"type":"topUpIsolatedOnlyMargin","asset":0,"leverage":"3"})
      assert Jason.decode!(body)["vaultAddress"] == @address
    end
  end

  describe "reserveRequestWeight" do
    test "omits destination entirely when not supplied", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          ReserveRequestWeight.request(10, private_key: @private_key)
        end)

      # An extra key would change the L1 action hash, so absence matters.
      assert raw == ~s({"type":"reserveRequestWeight","weight":10})
    end

    test "appends destination after weight when supplied", %{bypass: bypass} do
      raw =
        capture_action(bypass, fn ->
          ReserveRequestWeight.request(10, destination: @address, private_key: @private_key)
        end)

      assert raw ==
               ~s({"type":"reserveRequestWeight","weight":10,"destination":"#{@address}"})
    end

    test "build_action/2 pins the key order" do
      assert Jason.encode!(ReserveRequestWeight.build_action(5)) ==
               ~s({"type":"reserveRequestWeight","weight":5})

      assert Jason.encode!(ReserveRequestWeight.build_action(5, @address)) ==
               ~s({"type":"reserveRequestWeight","weight":5,"destination":"#{@address}"})
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
