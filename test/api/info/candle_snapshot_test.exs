defmodule Hyperliquid.Api.Info.CandleSnapshotTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Info.CandleSnapshot

  setup do
    bypass = Bypass.open()
    Application.put_env(:hyperliquid, :http_url, "http://localhost:#{bypass.port}")

    {:ok, bypass: bypass}
  end

  test "keeps open time (t) and close time (T) as distinct values", %{bypass: bypass} do
    Bypass.expect(bypass, "POST", "/info", fn conn ->
      resp = [
        %{
          "t" => 1_785_153_600_000,
          "T" => 1_785_157_199_999,
          "s" => "LDO",
          "i" => "1h",
          "o" => "0.40148",
          "c" => "0.40341",
          "h" => "0.40447",
          "l" => "0.3975",
          "v" => "383090.9",
          "n" => 920
        }
      ]

      Plug.Conn.put_resp_header(conn, "content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(resp))
    end)

    assert {:ok, %{candles: [candle]}} =
             CandleSnapshot.request("LDO", "1h", 1_785_153_600_000, 1_785_157_200_000)

    assert candle.t == 1_785_153_600_000
    assert Map.get(candle, :T) == 1_785_157_199_999
  end
end
