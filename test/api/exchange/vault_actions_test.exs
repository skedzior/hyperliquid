defmodule Hyperliquid.Api.Exchange.VaultActionsTest do
  @moduledoc """
  `vaultTransfer.usd` and `vaultDistribute.usd` are `UnsignedInteger` on the
  wire (`float * 1e6`) — see `@nktkas/hyperliquid`
  `src/api/exchange/_methods/vaultTransfer.ts` and `vaultDistribute.ts`, and
  `hyperliquid-python-sdk`'s `vault_usd_transfer/3`.

  Live testnet (2026-09-09) rejected the string form with
  `HTTP 422: Failed to deserialize the JSON body into the target type`, and
  `vaultDistribute` was missing the field entirely. The signing vectors in
  `test/signing_vectors_test.exs` hash a hand-written JSON string, so they could
  not catch either bug — these tests assert on what the *modules* actually put
  on the wire.
  """

  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.{VaultDistribute, VaultTransfer}

  @private_key "0000000000000000000000000000000000000000000000000000000000000001"
  @vault "0x1719884eb866cb12b2287399b15f7db5e7d775ea"

  setup do
    bypass = Bypass.open()
    Application.put_env(:hyperliquid, :http_url, "http://localhost:#{bypass.port}")

    {:ok, bypass: bypass}
  end

  defp capture(bypass, fun) do
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
    [_, action] = Regex.run(~r/"action":(.*),"nonce"/U, body)
    action
  end

  test "vaultTransfer sends usd as an unsigned integer, in schema order", %{bypass: bypass} do
    action =
      capture(bypass, fn ->
        VaultTransfer.request(@vault, true, 5_000_000, private_key: @private_key)
      end)

    assert action ==
             ~s({"type":"vaultTransfer","vaultAddress":"#{@vault}","isDeposit":true,"usd":5000000})
  end

  test "vaultTransfer rejects a stringified amount at the call site" do
    assert_raise FunctionClauseError, fn ->
      VaultTransfer.request(@vault, true, "5.0", private_key: @private_key)
    end
  end

  test "vaultDistribute carries usd", %{bypass: bypass} do
    action =
      capture(bypass, fn ->
        VaultDistribute.request(@vault, 1_000_000, private_key: @private_key)
      end)

    assert action == ~s({"type":"vaultDistribute","vaultAddress":"#{@vault}","usd":1000000})
  end

  test "vaultDistribute accepts 0 (close the vault)", %{bypass: bypass} do
    action =
      capture(bypass, fn ->
        VaultDistribute.request(@vault, 0, private_key: @private_key)
      end)

    assert action == ~s({"type":"vaultDistribute","vaultAddress":"#{@vault}","usd":0})
  end
end
