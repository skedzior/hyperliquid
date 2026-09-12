defmodule Hyperliquid.Api.Subscription.FastAssetCtxsTest do
  @moduledoc """
  Unit tests for the `fastAssetCtxs` channel, whose payload arrives as base64 +
  raw DEFLATE (RFC 1951) compressed JSON. Fixtures are generated locally with
  `:zlib` so the test never touches the network.
  """
  use ExUnit.Case, async: true

  alias Hyperliquid.Api.Subscription.FastAssetCtxs

  @event %{
    "BTC" => %{"markPx" => "50000.0", "midPx" => "49999.5"},
    "ETH" => %{"markPx" => "2500.0", "midPx" => nil},
    "HYPE" => %{"midPx" => "40.0"}
  }

  # Mirror of the server side: raw DEFLATE (negative window bits => no zlib
  # header), then base64.
  defp encode(term) do
    json = Jason.encode!(term)
    z = :zlib.open()

    try do
      :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
      compressed = :zlib.deflate(z, json, :finish)
      :zlib.deflateEnd(z)
      compressed |> IO.iodata_to_binary() |> Base.encode64()
    after
      :zlib.close(z)
    end
  end

  describe "build_request/1" do
    test "no params" do
      assert {:ok, %{type: "fastAssetCtxs"}} = FastAssetCtxs.build_request()
      assert {:ok, %{type: "fastAssetCtxs"}} = FastAssetCtxs.build_request(%{})
    end

    test "shares a connection" do
      assert FastAssetCtxs.__subscription_info__().connection_type == :shared
    end
  end

  describe "decode/1" do
    test "round-trips a base64 + raw DEFLATE payload" do
      assert {:ok, decoded} = FastAssetCtxs.decode(encode(@event))
      assert decoded == @event
    end

    test "handles a payload large enough to span multiple inflate chunks" do
      big =
        Map.new(1..5_000, fn i ->
          {"COIN#{i}", %{"markPx" => "#{i}.0", "midPx" => "#{i}.5"}}
        end)

      encoded = encode(big)
      assert {:ok, decoded} = FastAssetCtxs.decode(encoded)
      assert map_size(decoded) == 5_000
      assert decoded["COIN4321"] == %{"markPx" => "4321.0", "midPx" => "4321.5"}
      # Compression is worth doing: the wire form is much smaller than the JSON.
      assert byte_size(encoded) < byte_size(Jason.encode!(big))
    end

    test "rejects non-base64 input" do
      assert {:error, :invalid_base64} = FastAssetCtxs.decode("not base64!!!")
    end

    test "rejects base64 that is not a deflate stream" do
      assert {:error, :inflate_failed} = FastAssetCtxs.decode(Base.encode64("plain text"))
    end

    test "reports JSON errors separately from inflate errors" do
      z = :zlib.open()
      :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
      compressed = :zlib.deflate(z, "{not json", :finish)
      :zlib.deflateEnd(z)
      :zlib.close(z)

      payload = compressed |> IO.iodata_to_binary() |> Base.encode64()
      assert {:error, {:json_decode_error, _}} = FastAssetCtxs.decode(payload)
    end
  end

  describe "preprocess/1" do
    test "decodes the compressed payload in place" do
      # preprocess/1 decompresses and then nests under :ctxs for the schema.
      assert FastAssetCtxs.preprocess(encode(@event)) == %{ctxs: @event}
    end

    test "passes an undecodable payload through instead of crashing" do
      assert FastAssetCtxs.preprocess("not base64!!!") == "not base64!!!"
    end

    test "passes an already-decoded map through" do
      assert FastAssetCtxs.preprocess(@event) == %{ctxs: @event}
    end
  end

  describe "changeset/2" do
    test "casts a bare coin => ctx map" do
      assert %Ecto.Changeset{valid?: true} =
               cs = FastAssetCtxs.changeset(FastAssetCtxs.preprocess(@event))

      assert Ecto.Changeset.apply_changes(cs).ctxs == @event
    end

    test "casts an already-wrapped map" do
      assert %Ecto.Changeset{valid?: true} = cs = FastAssetCtxs.changeset(%{"ctxs" => @event})
      assert Ecto.Changeset.apply_changes(cs).ctxs == @event
    end
  end

  describe "helpers" do
    test "mark_px/mid_px read from raw events and structs" do
      event = FastAssetCtxs.preprocess(@event)

      assert FastAssetCtxs.mark_px(event, "BTC") == {:ok, "50000.0"}
      assert FastAssetCtxs.mid_px(event, "ETH") == {:error, :not_found}
      assert FastAssetCtxs.mark_px(event, "HYPE") == {:error, :not_found}
      assert FastAssetCtxs.mid_px(event, "NOPE") == {:error, :not_found}

      struct = %FastAssetCtxs{ctxs: @event}
      assert FastAssetCtxs.mark_px(struct, "BTC") == {:ok, "50000.0"}
    end

    test "merge/2 applies incremental updates over a snapshot" do
      update = %{"BTC" => %{"markPx" => "51000.0", "midPx" => "50999.0"}}
      merged = FastAssetCtxs.merge(@event, update)

      assert merged["BTC"] == %{"markPx" => "51000.0", "midPx" => "50999.0"}
      # untouched coins survive
      assert merged["ETH"] == @event["ETH"]
      assert map_size(merged) == 3
    end
  end
end
