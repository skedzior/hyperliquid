defmodule Hyperliquid.Api.InfoTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Info
  alias Hyperliquid.Api.Info.AllMids

  setup do
    bypass = Bypass.open()

    # Point both API bases at the test server (info uses http_url)
    Application.put_env(:hyperliquid, :http_url, "http://localhost:#{bypass.port}")
    Application.put_env(:hyperliquid, :rpc_url, "http://localhost:#{bypass.port}")

    {:ok, bypass: bypass}
  end

  test "all_mids posts to /info with type=allMids and returns decoded json", %{bypass: bypass} do
    Bypass.expect(bypass, "POST", "/info", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["type"] == "allMids"

      # allMids answers a bare coin -> price map (not an envelope).
      resp = %{"BTC" => "50000.0", "ETH" => "2500.0", "kPEPE" => "0.0182", "@107" => "41.2"}

      Plug.Conn.put_resp_header(conn, "content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(resp))
    end)

    assert {:ok, %Hyperliquid.Api.Info.AllMids{} = all_mids} = Info.all_mids()

    # H5: data keys must survive key transformation untouched.
    assert {:ok, "50000.0"} = AllMids.get_mid(all_mids, "BTC")
    assert {:ok, "0.0182"} = AllMids.get_mid(all_mids, "kPEPE")
    assert {:ok, "41.2"} = AllMids.get_mid(all_mids, "@107")
    assert Enum.sort(AllMids.get_coins(all_mids)) == ["@107", "BTC", "ETH", "kPEPE"]
  end

  test "clearinghouse_state declares user required and dex optional", %{bypass: bypass} do
    # `dex` was widened from required to optional (matching nktkas); `user` is
    # still the only required param. This test previously asserted an
    # `ArgumentError` for a nil `user` — the DSL has never validated required
    # params client-side, so that assertion could never pass. A nil `user` is
    # sent to the API, which rejects it.
    info = Hyperliquid.Api.Info.ClearinghouseState.__endpoint_info__()

    assert info.params == [:user]
    assert info.optional_params == [:dex]

    # A nil `user` is sent to the API, which rejects it with a 422.
    Bypass.expect_once(bypass, "POST", "/info", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["type"] == "clearinghouseState"
      assert payload["user"] == nil

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(422, ~s({"error":"Failed to deserialize the JSON body"}))
    end)

    assert {:error, %Hyperliquid.Error{status_code: 422}} = Info.clearinghouse_state(nil)
  end
end
