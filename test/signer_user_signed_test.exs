defmodule Hyperliquid.SignerUserSignedTest do
  use ExUnit.Case, async: true

  alias Hyperliquid.Signer

  @priv_key "0x822e9959e022b78423eb653a62ea0020cd283e71a2a8133a6ff2aeffaf373cff"

  # Vector: `@nktkas/hyperliquid` tests/signing/mod.test.ts, `USER_SIGNED_ACTION`.
  #
  # The vector signs with `signatureChainId: "0x66eee"` (421614), which is both
  # the Rust `chain/1` default and `Hyperliquid.Config.signature_chain_id/0`'s
  # default, so the generic `sign_typed_data/5` path and the legacy per-action
  # NIFs both reproduce it. Every user-signed action module in
  # `lib/hyperliquid/api/exchange/` uses the generic path via `UserSigned`.
  #
  # EIP-712 hashes the message field-by-field in the order the type declares,
  # so the message must be a `Jason.OrderedObject` in the nktkas field order,
  # not a plain map (small-map key order follows atom term order).
  @domain Jason.OrderedObject.new([
            {"name", "HyperliquidSignTransaction"},
            {"version", "1"},
            {"chainId", 421_614},
            {"verifyingContract", "0x0000000000000000000000000000000000000000"}
          ])

  @types Jason.OrderedObject.new([
           {"HyperliquidTransaction:UsdSend",
            [
              Jason.OrderedObject.new([{"name", "hyperliquidChain"}, {"type", "string"}]),
              Jason.OrderedObject.new([{"name", "destination"}, {"type", "string"}]),
              Jason.OrderedObject.new([{"name", "amount"}, {"type", "string"}]),
              Jason.OrderedObject.new([{"name", "time"}, {"type", "uint64"}])
            ]}
         ])

  @message Jason.OrderedObject.new([
             {"hyperliquidChain", "Mainnet"},
             {"signatureChainId", "0x66eee"},
             {"destination", "0x1234567890123456789012345678901234567890"},
             {"amount", "1000"},
             {"time", 1_234_567_890}
           ])

  describe "usdSend EIP-712 signature" do
    test "matches vector from TS suite (signatureChainId 0x66eee)" do
      sig =
        Signer.sign_typed_data(
          @priv_key,
          Jason.encode!(@domain),
          Jason.encode!(@types),
          Jason.encode!(@message),
          "HyperliquidTransaction:UsdSend"
        )
        |> Map.take(["r", "s", "v"])

      assert sig["r"] == "0xf777c38efe7c24cc71209526ae608f4e384d0586edf578f0e97b4b9f7c7adcc6"
      assert sig["s"] == "0x104a4a97c48ae77bf5bd777bdd45fe72d8f5ff29116b5ff64fd8cfe4ea610786"
      assert sig["v"] == 28
    end

    test "the legacy sign_usd_send/5 NIF reproduces the same vector" do
      sig =
        Signer.sign_usd_send(
          @priv_key,
          "0x1234567890123456789012345678901234567890",
          "1000",
          1_234_567_890,
          true
        )

      # The Rust `chain/1` default moved to 421614 in 0.3.1, so the standalone
      # per-action NIFs now agree with the generic `sign_typed_data/5` path and
      # with the reference SDKs. They are kept only for ABI compatibility; every
      # user-signed module goes through `Hyperliquid.Api.Exchange.UserSigned`.
      assert sig["r"] == "0xf777c38efe7c24cc71209526ae608f4e384d0586edf578f0e97b4b9f7c7adcc6"
      assert sig["s"] == "0x104a4a97c48ae77bf5bd777bdd45fe72d8f5ff29116b5ff64fd8cfe4ea610786"
      assert sig["v"] == 28
    end
  end
end
