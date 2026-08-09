defmodule Hyperliquid.SignerL1Test do
  use ExUnit.Case, async: true

  alias Hyperliquid.Api.ActionEncoder
  alias Hyperliquid.Signer

  @priv_key "0x822e9959e022b78423eb653a62ea0020cd283e71a2a8133a6ff2aeffaf373cff"

  @action %{
    type: "order",
    orders: [
      %{
        a: 0,
        b: true,
        p: "30000",
        s: "0.1",
        r: false,
        t: %{limit: %{tif: "Gtc"}}
      }
    ],
    grouping: "na"
  }

  @nonce 1_234_567_890
  @vault "0x1234567890123456789012345678901234567890"
  @expires 1_234_567_890

  describe "action hash (connection id)" do
    test "without vaultAddress and expiresAfter (mainnet)" do
      {:ok, action_json} = ActionEncoder.encode(@action)

      assert <<"0x", _::binary>> =
               hash = Signer.compute_connection_id_ex(action_json, @nonce, nil, nil)

      assert hash == "0x25367e0dba84351148288c2233cd6130ed6cec5967ded0c0b7334f36f957cc90"
    end

    test "with vaultAddress" do
      {:ok, action_json} = ActionEncoder.encode(@action)

      assert Signer.compute_connection_id_ex(action_json, @nonce, @vault, nil) ==
               "0x214e2ea3270981b6fd18174216691e69f56872663139d396b10ded319cb4bb1e"
    end

    test "with expiresAfter" do
      {:ok, action_json} = ActionEncoder.encode(@action)

      assert Signer.compute_connection_id_ex(action_json, @nonce, nil, @expires) ==
               "0xc30b002ba3775e4c31c43c1dfd3291dfc85c6ae06c6b9f393991de86cad5fac7"
    end

    test "with vaultAddress and expiresAfter" do
      {:ok, action_json} = ActionEncoder.encode(@action)

      assert Signer.compute_connection_id_ex(action_json, @nonce, @vault, @expires) ==
               "0x2d62412aa0fc57441b5189841d81554a6a9680bf07204e1454983a9ca44f0744"
    end
  end

  describe "sign L1 action" do
    defp hex32(<<"0x", rest::binary>>) do
      "0x" <> String.pad_leading(rest, 64, "0")
    end

    defp sign(is_mainnet?, vault, expires) do
      {:ok, action_json} = ActionEncoder.encode(@action)

      Signer.sign_exchange_action_ex(@priv_key, action_json, @nonce, is_mainnet?, vault, expires)
      |> Map.take(["r", "s", "v"])
    end

    test "mainnet: without vaultAddress + expiresAfter" do
      sig = sign(true, nil, nil)

      assert hex32(sig["r"]) ==
               "0x61078d8ffa3cb591de045438a1ae2ed299b271891d1943a33901e7cfb3a31ed8"

      assert hex32(sig["s"]) ==
               "0x0e91df4f9841641d3322dad8d932874b74d7e082cdb5b533f804964a6963aef9"

      assert sig["v"] == 28
    end

    test "mainnet: with vaultAddress" do
      sig = sign(true, @vault, nil)

      assert hex32(sig["r"]) ==
               "0x77151b3ae29b83c8affb3791568c6452019ba8c30019236003abb1efcd809433"

      assert hex32(sig["s"]) ==
               "0x55668c02f6ad4a1c335ce99987b7545984c4edc1765fe52cf115a423dc8279bb"

      assert sig["v"] == 27
    end

    test "mainnet: with expiresAfter" do
      sig = sign(true, nil, @expires)

      assert hex32(sig["r"]) ==
               "0x162a52128fb58bc6adb783e3d36913c53127851144fc45c5603a51e97b9202fd"

      assert hex32(sig["s"]) ==
               "0x469571eb0a2101a32f81f9584e15fd35c723a6089e106f4f33798dbccf7cd416"

      assert sig["v"] == 28
    end

    test "mainnet: with vaultAddress + expiresAfter" do
      sig = sign(true, @vault, @expires)

      assert hex32(sig["r"]) ==
               "0x78fcca006d7fdfaf1f66978ef7a60280246fc3e7a5b39a68a1656c3e42c58bf1"

      assert hex32(sig["s"]) ==
               "0x61a09957de7f0886c2bdffb7a94e3a257bf240796883ea6ceaf4d0be37055cdd"

      assert sig["v"] == 27
    end

    test "testnet: without vaultAddress + expiresAfter" do
      sig = sign(false, nil, nil)

      assert hex32(sig["r"]) ==
               "0x6b0283a894d87b996ad0182b86251cc80d27d61ef307449a2ed249a508ded1f7"

      assert hex32(sig["s"]) ==
               "0x6f884e79f4a0a10af62db831af6f8e03b3f11d899eb49b352f836746ee9226da"

      assert sig["v"] == 27
    end

    test "testnet: with vaultAddress" do
      sig = sign(false, @vault, nil)

      assert hex32(sig["r"]) ==
               "0x294a6cf713483c129be9af5c7450aca59c9082f391f02325715c0d04b7f48ac1"

      assert hex32(sig["s"]) ==
               "0x119cfd947dcd2da1d1064a9d08bcf07e01fc9b72dd7cca69a988c74249e300f0"

      assert sig["v"] == 27
    end

    test "testnet: with expiresAfter" do
      sig = sign(false, nil, @expires)

      assert hex32(sig["r"]) ==
               "0x5094989a7c0317db6553f21dd7f90d43415e8bd01af03829de249d4ea0aa5f66"

      assert hex32(sig["s"]) ==
               "0x491d04966e81662bd4e70d607fac30e71803c01733f4f66ff7299b0470675b8b"

      assert sig["v"] == 27
    end

    test "testnet: with vaultAddress + expiresAfter" do
      sig = sign(false, @vault, @expires)

      assert hex32(sig["r"]) ==
               "0x3a0bbbd9fadca54f58a2b7050899cecb97f68b2f693c63e91ca60510427326d7"

      assert hex32(sig["s"]) ==
               "0x60f75f12cae7b9dc18b889406192afcaf13f40d2f8c68cc01f7f83f3fb5deb23"

      assert sig["v"] == 27
    end
  end
end
