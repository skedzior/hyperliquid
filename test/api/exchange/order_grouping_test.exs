defmodule Hyperliquid.Api.Exchange.OrderGroupingTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.ActionEncoder
  alias Hyperliquid.Api.Exchange.Order
  alias Hyperliquid.Signer

  @nonce 1_234_567_890

  setup do
    bypass = Bypass.open()
    prev_url = Application.get_env(:hyperliquid, :http_url)
    Application.put_env(:hyperliquid, :http_url, "http://localhost:#{bypass.port}")

    Bypass.stub(bypass, "POST", "/info", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{}))
    end)

    on_exit(fn ->
      if prev_url,
        do: Application.put_env(:hyperliquid, :http_url, prev_url),
        else: Application.delete_env(:hyperliquid, :http_url)
    end)

    {:ok, bypass: bypass}
  end

  # build_action/3 is private; exercise it through the same encoding the signing
  # path uses by rebuilding the action from Order.limit/5 output.
  defp action(orders, grouping) do
    %{
      type: "order",
      orders:
        Enum.map(orders, fn o ->
          %{
            a: o.asset,
            b: o.is_buy,
            p: o.limit_px,
            s: o.sz,
            r: o.reduce_only,
            t: %{limit: %{tif: o.tif}}
          }
        end),
      grouping: grouping
    }
  end

  describe "priority-rate grouping" do
    test "encodes as the documented {\"p\": rate} object" do
      order = Order.limit(0, true, "30000", "0.1", tif: "Ioc")

      assert {:ok, json} = ActionEncoder.encode(action([order], %{p: 12345}))

      assert json ==
               ~s({"type":"order","orders":[{"a":0,"b":true,"p":"30000","s":"0.1","r":false,"t":{"limit":{"tif":"Ioc"}}}],"grouping":{"p":12345}})
    end

    test "hashes to the reference connection id" do
      order = Order.limit(0, true, "30000", "0.1", tif: "Ioc")
      {:ok, json} = ActionEncoder.encode(action([order], %{p: 12345}))

      # Reference value from the Python SDK's action_hash/4.
      assert Signer.compute_connection_id_ex(json, @nonce, nil, nil) ==
               "0x5e5d85104254d23a41f4efbbec00cef8157e46539c9c5c5be94d0ae43d20b6f6"
    end
  end

  describe "place_batch/3 wire format" do
    # Priority grouping needs the Grouping enum added to the Rust Actions struct.
    # The published v0.2.2 precompiled NIF still types grouping as a String and
    # rejects it with "invalid type: map, expected a string", so this only runs
    # against a NIF built from source (HYPERLIQUID_BUILD_NIF=1).
    @tag :requires_native_build
    test "sends priority grouping as {\"p\": rate}", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["action"]["grouping"] == %{"p" => 12345}

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"status" => "ok"}))
      end)

      order = Order.limit(0, true, "30000", "0.1", tif: "Ioc")

      assert {:ok, _} =
               Order.place_batch([order], {:priority, 12345}, private_key: test_key())
    end

    test "sends the action with canonical field order", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        # The body must carry the same field order that was hashed, otherwise
        # the exchange recomputes a different connection id.
        assert body =~ ~s("type":"order")
        assert body =~ ~s({"a":0,"b":true,"p":"30000","s":"0.1","r":false,"t":)

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"status" => "ok"}))
      end)

      order = Order.limit(0, true, "30000", "0.1", tif: "Gtc")
      assert {:ok, _} = Order.place_batch([order], :na, private_key: test_key())
    end

    test "legacy string groupings still work", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["action"]["grouping"] == "positionTpsl"

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"status" => "ok"}))
      end)

      order = Order.limit(0, true, "30000", "0.1")

      assert {:ok, _} =
               Order.place_batch([order], :position_tpsl, private_key: test_key())
    end
  end

  describe "grouping formatting" do
    # format_grouping/1 is private, so drive it through place_batch/3's argument
    # validation by asserting on the error it raises for out-of-range rates.
    test "rejects a priority rate above 100%" do
      order = Order.limit(0, true, "30000", "0.1", tif: "Ioc")

      assert_raise ArgumentError, ~r/between 0 and 100000000/, fn ->
        Order.place_batch([order], {:priority, 100_000_001}, private_key: test_key())
      end
    end

    test "rejects a non-integer priority rate" do
      order = Order.limit(0, true, "30000", "0.1", tif: "Ioc")

      assert_raise ArgumentError, ~r/must be an integer/, fn ->
        Order.place_batch([order], {:priority, 0.5}, private_key: test_key())
      end
    end
  end

  describe "time in force" do
    test "FrontendMarket is carried through to the wire" do
      order = Order.limit(0, true, "30000", "0.1", tif: "FrontendMarket")

      assert {:ok, json} = ActionEncoder.encode(action([order], "na"))
      assert json =~ ~s("tif":"FrontendMarket")
    end

    for tif <- ~w(Gtc Ioc Alo FrontendMarket) do
      test "#{tif} round-trips through Order.limit/5" do
        assert %{tif: unquote(tif)} = Order.limit(0, true, "30000", "0.1", tif: unquote(tif))
      end
    end
  end

  defp test_key, do: "0x822e9959e022b78423eb653a62ea0020cd283e71a2a8133a6ff2aeffaf373cff"
end
