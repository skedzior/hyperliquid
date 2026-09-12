defmodule Hyperliquid.Transport.HttpTest do
  use ExUnit.Case, async: false

  alias Hyperliquid.Error
  alias Hyperliquid.Transport.Http

  @signature %{"r" => "0x1", "s" => "0x2", "v" => 27}

  setup do
    bypass = Bypass.open()
    Application.put_env(:hyperliquid, :http_url, "http://localhost:#{bypass.port}")

    # Keep retry backoff negligible for the retry tests.
    Application.put_env(:hyperliquid, :http_retry_base_delay, 1)
    Application.put_env(:hyperliquid, :http_max_retry_delay, 5)

    on_exit(fn ->
      Application.delete_env(:hyperliquid, :http_retry_base_delay)
      Application.delete_env(:hyperliquid, :http_max_retry_delay)
      Application.delete_env(:hyperliquid, :http_max_retries)
    end)

    # The Cache.Warmer may issue background /info calls into this Bypass;
    # absorb them so they neither fail the test nor pollute request counters.
    Bypass.stub(bypass, "POST", "/info", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, "{}")
    end)

    {:ok, bypass: bypass, url: "http://localhost:#{bypass.port}/probe"}
  end

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.resp(status, Jason.encode!(body))
  end

  describe "exchange response classification (H4)" do
    test "top-level err is an error, not {:ok, _}", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/exchange", fn conn ->
        json(conn, 200, %{
          "status" => "err",
          "response" => "Insufficient margin to place order"
        })
      end)

      assert {:error, %Error{} = error} =
               Http.exchange_request(%{type: "order"}, @signature, 1)

      assert error.type == :exchange
      assert error.message =~ "Insufficient margin"
      assert %{"status" => "err"} = error.response
    end

    test "batch with all statuses ok is {:ok, _}", %{bypass: bypass} do
      body = %{
        "status" => "ok",
        "response" => %{
          "type" => "order",
          "data" => %{
            "statuses" => [
              %{"resting" => %{"oid" => 1}},
              %{"filled" => %{"oid" => 2, "totalSz" => "1.0", "avgPx" => "100"}}
            ]
          }
        }
      }

      Bypass.expect_once(bypass, "POST", "/exchange", fn conn -> json(conn, 200, body) end)

      assert {:ok, %{"status" => "ok"}} = Http.exchange_request(%{type: "order"}, @signature, 1)
    end

    test "batch with one rejected status is a partial rejection carrying all statuses", %{
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "POST", "/exchange", fn conn ->
        json(conn, 200, %{
          "status" => "ok",
          "response" => %{
            "type" => "order",
            "data" => %{
              "statuses" => [
                %{"resting" => %{"oid" => 1}},
                %{"error" => "Order price cannot be more than 95% away from the reference price"},
                %{"filled" => %{"oid" => 3}}
              ]
            }
          }
        })
      end)

      assert {:error, %Error{} = error} =
               Http.exchange_request(%{type: "order"}, @signature, 1)

      assert error.type == :partial_rejection
      assert error.message =~ "1/3 action(s) rejected"
      assert error.message =~ "1: Order price cannot"

      # The FULL statuses list survives, so callers can see what did rest/fill.
      assert [%{"resting" => _}, %{"error" => _}, %{"filled" => _}] = error.statuses
    end

    test "single status error is an error", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/exchange", fn conn ->
        json(conn, 200, %{
          "status" => "ok",
          "response" => %{
            "type" => "cancel",
            "data" => %{"status" => %{"error" => "Order was never placed, already canceled"}}
          }
        })
      end)

      assert {:error, %Error{type: :exchange, message: msg}} =
               Http.exchange_request(%{type: "cancel"}, @signature, 1)

      assert msg =~ "already canceled"
    end

    test "user-signed requests are classified too", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/exchange", fn conn ->
        json(conn, 200, %{"status" => "err", "response" => "Must deposit before trading"})
      end)

      assert {:error, %Error{type: :exchange}} =
               Http.user_signed_request(%{type: "usdSend"}, @signature, 1)
    end

    test "responses without a status envelope pass through", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/exchange", fn conn ->
        json(conn, 200, %{"status" => "ok", "response" => %{"type" => "default"}})
      end)

      assert {:ok, %{"status" => "ok"}} =
               Http.exchange_request(%{type: "createSubAccount"}, @signature, 1)
    end
  end

  describe "429 handling (H12)" do
    test "reads retry a 429 and then succeed", %{bypass: bypass, url: url} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, "POST", "/probe", fn conn ->
        n = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

        if n == 0 do
          conn
          |> Plug.Conn.put_resp_header("retry-after", "0")
          |> Plug.Conn.resp(429, "rate limited")
        else
          json(conn, 200, %{"BTC" => "50000.0"})
        end
      end)

      assert {:ok, %{"BTC" => "50000.0"}} = Http.post(url, %{})
      assert Agent.get(counter, & &1) == 2
    end

    test "a persistent 429 surfaces as :rate_limited with retry_after", %{
      bypass: bypass,
      url: url
    } do
      Application.put_env(:hyperliquid, :http_max_retries, 1)

      Bypass.expect(bypass, "POST", "/probe", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "2")
        |> Plug.Conn.resp(429, "rate limited")
      end)

      assert {:error, %Error{} = error} = Http.post(url, %{})
      assert error.type == :rate_limited
      assert error.status_code == 429
      # Retry-After: 2 seconds, capped by http_max_retry_delay for sleeping but
      # reported verbatim in milliseconds.
      assert error.retry_after == 2_000
    end

    test "exchange writes are never retried", %{bypass: bypass} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        Agent.update(counter, &(&1 + 1))
        Plug.Conn.resp(conn, 429, "rate limited")
      end)

      assert {:error, %Error{type: :rate_limited}} =
               Http.exchange_request(%{type: "order"}, @signature, 1)

      assert Agent.get(counter, & &1) == 1
    end

    test "5xx on a read is retried, then reported", %{bypass: bypass, url: url} do
      Application.put_env(:hyperliquid, :http_max_retries, 2)
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, "POST", "/probe", fn conn ->
        Agent.update(counter, &(&1 + 1))
        Plug.Conn.resp(conn, 503, "unavailable")
      end)

      assert {:error, %Error{status_code: 503, type: :http}} = Http.post(url, %{})
      assert Agent.get(counter, & &1) == 3
    end
  end

  describe "telemetry (M10)" do
    test "emits a request span with documented metadata", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "POST", "/probe", fn conn -> json(conn, 200, %{"ok" => true}) end)

      test_pid = self()
      handler = {__MODULE__, System.unique_integer()}

      :telemetry.attach_many(
        handler,
        [
          [:hyperliquid, :http, :request, :start],
          [:hyperliquid, :http, :request, :stop]
        ],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      assert {:ok, _} = Http.post(url, %{})

      assert_receive {:telemetry, [:hyperliquid, :http, :request, :start], _, start_meta}
      assert start_meta.module == Http
      assert start_meta.method == :post
      assert start_meta.request_type == :info

      assert_receive {:telemetry, [:hyperliquid, :http, :request, :stop], measurements, stop_meta}
      assert is_integer(measurements.duration)
      assert stop_meta.result == :ok
    end
  end

  describe "key transformation (H5)" do
    test "camelCase field names are snake_cased, data keys are not", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "POST", "/probe", fn conn ->
        json(conn, 200, %{
          "assetPositions" => [%{"szDecimals" => 2, "coin" => "BTC"}],
          "l2Book" => %{"nSigFigs" => 5},
          "BTC" => "1",
          "kPEPE" => "2",
          "@107" => "3",
          "0xAbC" => "4",
          "USDC" => "5"
        })
      end)

      assert {:ok, data} = Http.post(url, %{})

      # Field names
      assert %{"asset_positions" => [%{"sz_decimals" => 2, "coin" => "BTC"}]} = data
      assert %{"l2_book" => %{"n_sig_figs" => 5}} = data

      # Data keys - untouched
      assert data["BTC"] == "1"
      assert data["kPEPE"] == "2"
      assert data["@107"] == "3"
      assert data["0xAbC"] == "4"
      assert data["USDC"] == "5"

      refute Map.has_key?(data, "b_t_c")
      refute Map.has_key?(data, "k_p_e_p_e")
    end
  end
end
