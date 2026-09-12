defmodule Hyperliquid.Api.MultiSigTest do
  @moduledoc """
  Deterministic signature-vector tests for `Hyperliquid.Api.MultiSig`.

  Vectors are lifted verbatim from `@nktkas/hyperliquid` v0.33.3
  `tests/signing/mod.test.ts` (`MULTI_SIG_L1`, `MULTI_SIG_USER_SIGNED`,
  `MULTI_SIG_USER_SET_ABSTRACTION`). Same private key + same payload must yield
  the same signatures. No network access.
  """
  use ExUnit.Case, async: true

  alias Hyperliquid.Api.MultiSig

  @priv_key "0x822e9959e022b78423eb653a62ea0020cd283e71a2a8133a6ff2aeffaf373cff"
  @leader "0xe5ca49fb3bd9a581f0d1ef9cb5d7177da08bf901"
  @multi_sig_user "0x1234567890123456789012345678901234567890"

  defp oo(entries), do: Jason.OrderedObject.new(entries)

  # nktkas L1_ACTION.action
  defp l1_action do
    oo([
      {"type", "order"},
      {"orders",
       [
         oo([
           {"a", 0},
           {"b", true},
           {"p", "30000"},
           {"s", "0.1"},
           {"r", false},
           {"t", oo([{"limit", oo([{"tif", "Gtc"}])}])}
         ])
       ]},
      {"grouping", "na"}
    ])
  end

  # nktkas USER_SIGNED_ACTION
  defp usd_send_action do
    oo([
      {"hyperliquidChain", "Mainnet"},
      {"signatureChainId", "0x66eee"},
      {"destination", "0x1234567890123456789012345678901234567890"},
      {"amount", "1000"},
      {"time", 1_234_567_890}
    ])
  end

  defp usd_send_types do
    oo([
      {"HyperliquidTransaction:UsdSend",
       [
         oo([{"name", "hyperliquidChain"}, {"type", "string"}]),
         oo([{"name", "destination"}, {"type", "string"}]),
         oo([{"name", "amount"}, {"type", "string"}]),
         oo([{"name", "time"}, {"type", "uint64"}])
       ]}
    ])
  end

  # nktkas MULTI_SIG_USER_SET_ABSTRACTION
  defp set_abstraction_action do
    oo([
      {"type", "userSetAbstraction"},
      {"signatureChainId", "0x66eee"},
      {"hyperliquidChain", "Testnet"},
      {"user", "0x3b4d2cc2e144a0044002506c8b44508e9ace82e9"},
      {"abstraction", "disabled"},
      {"nonce", 1_780_130_409_592}
    ])
  end

  defp set_abstraction_types do
    oo([
      {"HyperliquidTransaction:UserSetAbstraction",
       [
         oo([{"name", "hyperliquidChain"}, {"type", "string"}]),
         oo([{"name", "user"}, {"type", "address"}]),
         oo([{"name", "abstraction"}, {"type", "string"}]),
         oo([{"name", "nonce"}, {"type", "uint64"}])
       ]}
    ])
  end

  defp entries(%Jason.OrderedObject{values: values}), do: values

  describe "outer_signer/1" do
    test "derives the lowercased leader address" do
      assert MultiSig.outer_signer(@priv_key) == @leader
    end
  end

  describe "build_payload/3" do
    test "lowercases both addresses and keeps the action last" do
      assert MultiSig.build_payload(
               "0x1234567890123456789012345678901234567890",
               "0xE5cA49Fb3bD9A581F0D1EF9CB5D7177Da08bf901",
               :action
             ) == [@multi_sig_user, @leader, :action]
    end
  end

  describe "trim_signature/1" do
    test "strips leading zeros from r and s" do
      assert MultiSig.trim_signature(%{r: "0x0012", s: "0x00", v: 27}) ==
               %{r: "0x12", s: "0x", v: 27}
    end
  end

  describe "payload_action/1" do
    test "maps userSetAbstraction abstraction to its single-letter code" do
      assert entries(MultiSig.payload_action(set_abstraction_action())) == [
               {"type", "userSetAbstraction"},
               {"signatureChainId", "0x66eee"},
               {"hyperliquidChain", "Testnet"},
               {"user", "0x3b4d2cc2e144a0044002506c8b44508e9ace82e9"},
               {"abstraction", "i"},
               {"nonce", 1_780_130_409_592}
             ]
    end

    test "maps the other abstraction values" do
      for {long, short} <- [{"unifiedAccount", "u"}, {"portfolioMargin", "p"}] do
        action = oo([{"type", "userSetAbstraction"}, {"abstraction", long}])

        assert {"abstraction", ^short} =
                 List.keyfind(entries(MultiSig.payload_action(action)), "abstraction", 0)
      end
    end

    test "leaves other actions untouched" do
      action = l1_action()
      assert MultiSig.payload_action(action) == action
    end
  end

  describe "sign_l1/2 (nktkas MULTI_SIG_L1 vector)" do
    test "produces the reference wrapper and outer signature" do
      assert {:ok, %{action: action, signature: signature, nonce: nonce}} =
               MultiSig.sign_l1([@priv_key],
                 multi_sig_user: @multi_sig_user,
                 signature_chain_id: "0x66eee",
                 action: l1_action(),
                 nonce: 1_234_567_890,
                 expires_after: nil,
                 mainnet: true
               )

      assert nonce == 1_234_567_890

      [
        {"type", "multiSig"},
        {"signatureChainId", "0x66eee"},
        {"signatures", [inner]},
        {"payload", payload}
      ] = entries(action)

      assert entries(inner) == [
               {"r", "0x12a4e2b7cfc2b5fc3d1e7847573de88bf1172731392be62fa6a9f2de3772b5ba"},
               {"s", "0x565f4ad818ae04b26624e548ed3d2a9d5a41a8b6460cfc1555a0fe07d6a56121"},
               {"v", 27}
             ]

      assert [
               {"multiSigUser", @multi_sig_user},
               {"outerSigner", @leader},
               {"action", inner_action}
             ] =
               entries(payload)

      assert inner_action == l1_action()

      assert signature == %{
               r: "0x6ce5dcb0b71db89f2b94f1427533013457e93d9b3f2b3d2b84bf8a0cb0ec008f",
               s: "0x04e8981a177b328bebaae28598827f0aeee8be5b6f62756d81f6e71830c2103d",
               v: 28
             }
    end

    test "two signers produce two inner signatures, leader first" do
      second = "0x0123456789012345678901234567890123456789012345678901234567890123"

      assert {:ok, %{action: action}} =
               MultiSig.sign_l1([@priv_key, second],
                 multi_sig_user: @multi_sig_user,
                 signature_chain_id: "0x66eee",
                 action: l1_action(),
                 nonce: 1_234_567_890,
                 expires_after: nil,
                 mainnet: true
               )

      {"signatures", [first, other]} = List.keyfind(entries(action), "signatures", 0)

      # The leader's inner signature is unchanged by the presence of a co-signer.
      assert {"r", "0x12a4e2b7cfc2b5fc3d1e7847573de88bf1172731392be62fa6a9f2de3772b5ba"} =
               List.keyfind(entries(first), "r", 0)

      refute entries(first) == entries(other)
    end
  end

  describe "sign_user_signed/2 (nktkas MULTI_SIG_USER_SIGNED vector)" do
    test "produces the reference wrapper and outer signature" do
      assert {:ok, %{action: action, signature: signature, nonce: nonce}} =
               MultiSig.sign_user_signed([@priv_key],
                 multi_sig_user: @multi_sig_user,
                 action: usd_send_action(),
                 types: usd_send_types()
               )

      assert nonce == 1_234_567_890

      [
        {"type", "multiSig"},
        {"signatureChainId", "0x66eee"},
        {"signatures", [inner]},
        {"payload", payload}
      ] = entries(action)

      assert entries(inner) == [
               {"r", "0xccc3921f376f76abb13fbc2892808acea98fa7471633c103430f407f75b64375"},
               {"s", "0x5b8f3608927dddafdc6b8a9a7ee95177caa9eb3e00c81af21892cb80b2bcfb15"},
               {"v", 28}
             ]

      assert {"action", inner_action} = List.keyfind(entries(payload), "action", 0)
      assert inner_action == usd_send_action()

      assert signature == %{
               r: "0x8927ad27b2ee54f6c4d6fb2ae4841835dd3c82c705a0afd055c8ce75ae3f4130",
               s: "0x7b555ee328026846560fed75501b1af2c4774636d5e06f09fe8c9faee9ee4075",
               v: 27
             }
    end
  end

  describe "sign_user_signed/2 with a distinct payload action (userSetAbstraction)" do
    test "signs the long form but serializes the short code (nktkas vector)" do
      action = set_abstraction_action()

      assert {:ok, %{action: wrapper, signature: signature, nonce: nonce}} =
               MultiSig.sign_user_signed([@priv_key],
                 multi_sig_user: @multi_sig_user,
                 action: action,
                 types: set_abstraction_types()
               )

      assert nonce == 1_780_130_409_592

      {"signatures", [inner]} = List.keyfind(entries(wrapper), "signatures", 0)

      assert entries(inner) == [
               {"r", "0xbeaaefe1f198650d10751bde2d398f2c27b00ce27df76b02a49e01b6cf674a0c"},
               {"s", "0x918a44e4ec29e6cba349ee48a177490d04e7b01ea23fd6845c274dc7150e91c"},
               {"v", 27}
             ]

      {"payload", payload} = List.keyfind(entries(wrapper), "payload", 0)
      {"action", payload_action} = List.keyfind(entries(payload), "action", 0)

      assert {"abstraction", "i"} = List.keyfind(entries(payload_action), "abstraction", 0)

      assert signature == %{
               r: "0x28159b1dc1496ca8d81c2aee9f2f73882b6f6f7f6a54509010cbdb08c5302699",
               s: "0x0d6832d115cd3149302afcbe1189875bc46e12f025d59aa618676f29cdc4ce6f",
               v: 28
             }

      # The caller's action is not mutated: the inner form stays long.
      assert {"abstraction", "disabled"} = List.keyfind(entries(action), "abstraction", 0)
    end

    test "an explicit :payload_action overrides the automatic mapping" do
      custom = oo([{"type", "userSetAbstraction"}, {"abstraction", "u"}])

      assert {:ok, %{action: wrapper}} =
               MultiSig.sign_user_signed([@priv_key],
                 multi_sig_user: @multi_sig_user,
                 action: set_abstraction_action(),
                 types: set_abstraction_types(),
                 payload_action: custom
               )

      {"payload", payload} = List.keyfind(entries(wrapper), "payload", 0)
      assert {"action", ^custom} = List.keyfind(entries(payload), "action", 0)
    end
  end

  describe "build_action/5 + sign_action/3" do
    test "the assembled wrapper hashes without its `type` discriminator" do
      inner = %{
        r: "0x12a4e2b7cfc2b5fc3d1e7847573de88bf1172731392be62fa6a9f2de3772b5ba",
        s: "0x565f4ad818ae04b26624e548ed3d2a9d5a41a8b6460cfc1555a0fe07d6a56121",
        v: 27
      }

      wrapper =
        MultiSig.build_action("0x66eee", [inner], @multi_sig_user, @leader, l1_action())

      assert MultiSig.sign_action(@priv_key, wrapper,
               nonce: 1_234_567_890,
               mainnet: true
             ) == %{
               r: "0x6ce5dcb0b71db89f2b94f1427533013457e93d9b3f2b3d2b84bf8a0cb0ec008f",
               s: "0x04e8981a177b328bebaae28598827f0aeee8be5b6f62756d81f6e71830c2103d",
               v: 28
             }
    end

    test "vaultAddress and expiresAfter change the outer signature" do
      inner = %{r: "0x12", s: "0x34", v: 27}
      wrapper = MultiSig.build_action("0x66eee", [inner], @multi_sig_user, @leader, l1_action())

      base = MultiSig.sign_action(@priv_key, wrapper, nonce: 1, mainnet: true)

      vault =
        MultiSig.sign_action(@priv_key, wrapper,
          nonce: 1,
          mainnet: true,
          vault_address: @multi_sig_user
        )

      exp = MultiSig.sign_action(@priv_key, wrapper, nonce: 1, mainnet: true, expires_after: 2)

      assert base != vault
      assert base != exp
      assert vault != exp
    end
  end
end
