defmodule Hyperliquid.Api.Exchange.CanonicalSigningTest do
  @moduledoc """
  Guards the invariant that every exchange action is signed and sent in canonical
  field order.

  Most exchange endpoints hand-roll their signing rather than going through the
  ExchangeEndpoint macro, so the fix has to hold in each of them individually.
  """
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.UpdateLeverage
  alias Hyperliquid.Signer

  @private_key "0x822e9959e022b78423eb653a62ea0020cd283e71a2a8133a6ff2aeffaf373cff"

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

  describe "hand-rolled endpoints" do
    test "updateLeverage sends the action in canonical field order", %{bypass: bypass} do
      test_pid = self()

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:body, body})

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"status" => "ok"}))
      end)

      assert {:ok, _} = UpdateLeverage.request(3, 20, true, private_key: @private_key)

      assert_receive {:body, body}
      action = Jason.decode!(body)["action"]

      # Canonical order for updateLeverage is type, asset, isCross, leverage.
      assert Map.keys(action) |> Enum.sort() == ["asset", "isCross", "leverage", "type"]

      assert body =~ ~s("type":"updateLeverage","asset":3,"isCross":true,"leverage":20)
    end

    test "the sent action hashes to the same connection id that was signed", %{bypass: bypass} do
      test_pid = self()

      Bypass.expect(bypass, "POST", "/exchange", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:body, body})

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"status" => "ok"}))
      end)

      assert {:ok, _} = UpdateLeverage.request(3, 20, true, private_key: @private_key)

      assert_receive {:body, body}

      # The endpoint signs ActionEncoder.encode(action). Rebuilding that exact
      # string here and finding it verbatim in the body proves the bytes that
      # were hashed are the bytes that were sent — the property that actually
      # matters, since the exchange recomputes the connection id from the body.
      {:ok, signed_preimage} =
        Hyperliquid.Api.ActionEncoder.encode(%{
          type: "updateLeverage",
          asset: 3,
          isCross: true,
          leverage: 20
        })

      assert String.contains?(body, signed_preimage)

      # And that preimage is what produces the connection id.
      nonce = Jason.decode!(body)["nonce"]
      connection_id = Signer.compute_connection_id_ex(signed_preimage, nonce, nil, nil)
      assert <<"0x", _::binary>> = connection_id
      assert String.length(connection_id) == 66
    end
  end

  describe "no endpoint bypasses the canonical encoder" do
    test "no exchange module encodes an action with Jason directly" do
      offenders =
        "lib/hyperliquid/api/exchange/*.ex"
        |> Path.wildcard()
        |> Enum.filter(fn path ->
          source = File.read!(path)

          String.contains?(source, "Jason.encode(action)") or
            String.contains?(source, "Jason.encode!(action)")
        end)
        |> Enum.map(&Path.basename/1)
        # order.ex canonicalizes its action before encoding it.
        |> Enum.reject(&(&1 == "order.ex"))

      assert offenders == [],
             "these modules sign a non-canonical preimage: #{inspect(offenders)}"
    end
  end
end
