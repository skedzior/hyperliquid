defmodule Hyperliquid.Api.Exchange.TwapCancelTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.TwapCancel

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

  describe "request/4" do
    test "builds correct action structure for basic twap cancel", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["action"]["type"] == "twapCancel"
        assert payload["action"]["a"] == 0
        assert payload["action"]["t"] == 12345

        Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
        )
      end)

      assert {:ok, %{"status" => "ok"}} =
               TwapCancel.request(0, 12345, private_key: @private_key)
    end

    test "builds correct action structure with vault address", %{bypass: bypass} do
      vault_address = "0x1234567890123456789012345678901234567890"

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["action"]["type"] == "twapCancel"
        assert payload["vaultAddress"] == vault_address

        Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"status" => "ok", "response" => %{"type" => "default"}})
        )
      end)

      assert {:ok, %{"status" => "ok"}} =
               TwapCancel.request(1, 67890,
                 private_key: @private_key,
                 vault_address: vault_address
               )
    end

    test "builds action with correct JSON field order" do
      asset = 0
      twap_id = 12345

      action =
        Jason.OrderedObject.new([
          {:type, "twapCancel"},
          {:a, asset},
          {:t, twap_id}
        ])

      action_json = Jason.encode!(action)

      expected_json = ~s({"type":"twapCancel","a":0,"t":12345})
      assert action_json == expected_json
    end

    test "builds action with different asset and twap_id values" do
      action =
        Jason.OrderedObject.new([
          {:type, "twapCancel"},
          {:a, 3},
          {:t, 999_888_777}
        ])

      action_json = Jason.encode!(action)
      expected_json = ~s({"type":"twapCancel","a":3,"t":999888777})
      assert action_json == expected_json
    end

    test "validates field names are correct" do
      action =
        Jason.OrderedObject.new([
          {:type, "twapCancel"},
          {:a, 0},
          {:t, 12345}
        ])

      action_map = Jason.decode!(Jason.encode!(action))

      assert Map.has_key?(action_map, "type")
      assert Map.has_key?(action_map, "a")
      assert Map.has_key?(action_map, "t")
      refute Map.has_key?(action_map, "asset")
      refute Map.has_key?(action_map, "twap_id")
      refute Map.has_key?(action_map, "twapId")
    end
  end
end
