defmodule Hyperliquid.Api.Exchange.DeployVariantsWp2Test do
  @moduledoc """
  Wire-shape tests for the perpDeploy / spotDeploy variants added from the official
  HIP-3 and HIP-1/HIP-2 deployer pages.
  """

  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.{PerpDeploy, SpotDeploy}

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
    raw = extract_action(body)
    {raw, Jason.decode!(body)["action"]}
  end

  describe "perpDeploy.setDeployerFees" do
    test "emits [[coin, {scale, growthMode}]]", %{bypass: bypass} do
      {raw, action} =
        capture(bypass, fn ->
          PerpDeploy.set_deployer_fees(
            [{"MYTOKEN", %{scale: "1.5", growth_mode: true}}],
            private_key: @private_key
          )
        end)

      assert action["type"] == "perpDeploy"

      assert String.contains?(
               raw,
               ~s("setDeployerFees":[["MYTOKEN",{"scale":"1.5","growthMode":true}]])
             )
    end

    test "the older setFeeScale / setGrowthModes variants still emit their own names", %{
      bypass: bypass
    } do
      # Kept deliberately: nktkas v0.33.3 emits these while the docs list only
      # setDeployerFees. See PerpDeploy's moduledoc discrepancy note.
      {_, action} =
        capture(bypass, fn ->
          PerpDeploy.set_fee_scale("mydex", "1.5", private_key: @private_key)
        end)

      assert action["setFeeScale"] == %{"dex" => "mydex", "scale" => "1.5"}
    end
  end

  describe "perpDeploy.setPerpAnnotation" do
    test "annotation fields are siblings of coin", %{bypass: bypass} do
      {raw, action} =
        capture(bypass, fn ->
          PerpDeploy.set_perp_annotation(
            %{
              coin: "MYTOKEN",
              category: "defi",
              description: "A perp",
              display_name: nil,
              keywords: ["a", "b"]
            },
            private_key: @private_key
          )
        end)

      assert String.contains?(
               raw,
               ~s("setPerpAnnotation":{"coin":"MYTOKEN","category":"defi",) <>
                 ~s("description":"A perp","displayName":null,"keywords":["a","b"]})
             )

      # displayName is nullable, not optional — it must always be present.
      assert Map.has_key?(action["setPerpAnnotation"], "displayName")
    end
  end

  describe "perpDeploy.disableDex" do
    test "payload is a bare string", %{bypass: bypass} do
      {_, action} =
        capture(bypass, fn -> PerpDeploy.disable_dex("mydex", private_key: @private_key) end)

      assert action["disableDex"] == "mydex"
    end
  end

  describe "spotDeploy quote-token disable variants" do
    test "disableQuoteToken", %{bypass: bypass} do
      {_, action} =
        capture(bypass, fn -> SpotDeploy.disable_quote_token(42, private_key: @private_key) end)

      assert action["disableQuoteToken"] == %{"token" => 42}
    end

    test "disableAlignedQuoteToken", %{bypass: bypass} do
      {_, action} =
        capture(bypass, fn ->
          SpotDeploy.disable_aligned_quote_token(42, private_key: @private_key)
        end)

      assert action["disableAlignedQuoteToken"] == %{"token" => 42}
    end
  end

  describe "spotDeploy.setTokenAnnotation" do
    test "annotation is nested under an `annotation` object", %{bypass: bypass} do
      {raw, action} =
        capture(bypass, fn ->
          SpotDeploy.set_token_annotation(
            42,
            %{
              category: "meme",
              description: "A token",
              display_name: "My Token",
              keywords: ["dog"]
            },
            private_key: @private_key
          )
        end)

      assert String.contains?(
               raw,
               ~s("setTokenAnnotation":{"token":42,"annotation":) <>
                 ~s({"category":"meme","description":"A token",) <>
                 ~s("displayName":"My Token","keywords":["dog"]}})
             )

      assert action["setTokenAnnotation"]["token"] == 42
    end

    test "displayName is emitted as null when omitted", %{bypass: bypass} do
      {_, action} =
        capture(bypass, fn ->
          SpotDeploy.set_token_annotation(
            42,
            %{category: "c", description: "d", keywords: []},
            private_key: @private_key
          )
        end)

      assert Map.has_key?(action["setTokenAnnotation"]["annotation"], "displayName")
      assert action["setTokenAnnotation"]["annotation"]["displayName"] == nil
    end
  end

  describe "spotDeploy.setDeployerLabel" do
    test "emits a label object", %{bypass: bypass} do
      {_, action} =
        capture(bypass, fn ->
          SpotDeploy.set_deployer_label("Acme Labs", private_key: @private_key)
        end)

      assert action["setDeployerLabel"] == %{"label" => "Acme Labs"}
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
