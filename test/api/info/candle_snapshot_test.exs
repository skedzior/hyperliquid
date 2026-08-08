defmodule Hyperliquid.Api.Info.CandleSnapshotTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Info.CandleSnapshot

  setup do
    bypass = Bypass.open()
    prev_url = Application.get_env(:hyperliquid, :http_url)
    Application.put_env(:hyperliquid, :http_url, "http://localhost:#{bypass.port}")

    on_exit(fn ->
      if prev_url do
        Application.put_env(:hyperliquid, :http_url, prev_url)
      else
        Application.delete_env(:hyperliquid, :http_url)
      end
    end)

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

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(resp))
    end)

    assert {:ok, %{candles: [candle]}} =
             CandleSnapshot.request("LDO", "1h", 1_785_153_600_000, 1_785_157_200_000)

    # Regression: "T" used to be downcased to "t", overwriting the open time and
    # silently dropping the close time entirely.
    assert candle.t == 1_785_153_600_000
    assert Map.get(candle, :T) == 1_785_157_199_999

    # The remaining single-letter keys must survive untouched too.
    assert candle.s == "LDO"
    assert candle.i == "1h"
    assert candle.o == "0.40148"
    assert candle.c == "0.40341"
    assert candle.h == "0.40447"
    assert candle.l == "0.3975"
    assert candle.v == "383090.9"
    assert candle.n == 920
  end

  test "close time survives into the postgres field mapping", %{bypass: bypass} do
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

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(resp))
    end)

    assert {:ok, %{candles: [candle]}} =
             CandleSnapshot.request("LDO", "1h", 1_785_153_600_000, 1_785_157_200_000)

    fields = CandleSnapshot.extract_postgres_fields(candle)

    assert fields.open_time == 1_785_153_600_000
    assert fields.close_time == 1_785_157_199_999
    refute fields.close_time == fields.open_time
  end
end
