import json, sys

d = json.load(open(sys.argv[1]))
out = open(sys.argv[2], "w")


def ex(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def nil(v):
    return "nil" if v is None else (ex(v) if isinstance(v, str) else str(v))


W = out.write

W('''defmodule Hyperliquid.SigningVectorsTest do
  @moduledoc """
  Cross-SDK signing vectors.

  Every vector in this file was produced by the **official Python SDK**
  (`hyperliquid-python-sdk`, `hyperliquid/utils/signing.py`) — an independent
  implementation with its own msgpack encoder, keccak and `eth_account`
  secp256k1 signer. Nothing here is a snapshot of this library's own output, so
  a key-order regression (H3) or a signing-path regression (H2) turns these red
  instead of silently producing rejected orders.

  Regenerate with `scripts/gen_signing_vectors.py` (see the module doc there).

  The generator's environment must use `msgpack >= 1.0` (`use_bin_type=True`),
  which encodes 32..255-byte strings as `str8` (`0xd9`) — the same encoding
  Rust's `rmp_serde` and `@std/msgpack` produce. A pre-1.0 `msgpack` emits
  `raw16` (`0xda`) and silently yields different, wrong hashes.

  """

  use ExUnit.Case, async: true

  alias Hyperliquid.Api.Exchange.Action
  alias Hyperliquid.Signer

''')

W("  @priv_key %s\n\n" % ex(d["private_key"]))

W("  # {name, action_json, nonce, vault, expires_after, has_declared_key_order?,\n")
W("  #  action_hash, mainnet_sig, testnet_sig}\n")
W("  @l1_vectors [\n")
for v in d["l1"]:
    W("    {%s, %s, %d, %s, %s, %s, %s, {%s, %s, %d}, {%s, %s, %d}},\n" % (
        ex(v["name"]), ex(v["json"]), v["nonce"], nil(v["vault"]), nil(v["expires"]),
        "true" if v["ordered"] else "false", ex(v["hash"]),
        ex(v["mainnet"]["r"]), ex(v["mainnet"]["s"]), v["mainnet"]["v"],
        ex(v["testnet"]["r"]), ex(v["testnet"]["s"]), v["testnet"]["v"]))
W("  ]\n\n")

W("  # {name, primary_type, domain_json, types_json, message_json, {r, s, v}}\n")
W("  @user_signed_vectors [\n")
for v in d["user_signed"]:
    W("    {%s, %s, %s, %s, %s, {%s, %s, %d}},\n" % (
        ex(v["name"]), ex(v["primary_type"]), ex(v["domain"]), ex(v["types"]), ex(v["message"]),
        ex(v["signature"]["r"]), ex(v["signature"]["s"]), v["signature"]["v"]))
W("  ]\n\n")

W('''  describe "L1 action hash (msgpack + keccak)" do
    for {name, json, nonce, vault, expires, _ordered, hash, _m, _t} <- @l1_vectors do
      test "#{name} hashes to the Python SDK's action_hash" do
        assert Signer.compute_connection_id_ex(
                 unquote(json),
                 unquote(nonce),
                 unquote(vault),
                 unquote(expires)
               ) == unquote(hash)
      end
    end
  end

  describe "L1 action signature (phantom agent EIP-712)" do
    for {name, json, nonce, vault, expires, _ordered, _hash, {mr, ms, mv}, {tr, ts, tv}} <-
          @l1_vectors do
      test "#{name} mainnet r/s/v matches the Python SDK" do
        assert Action.sign_json(
                 @priv_key,
                 unquote(json),
                 unquote(nonce),
                 unquote(vault),
                 unquote(expires),
                 true
               ) == {:ok, %{r: unquote(mr), s: unquote(ms), v: unquote(mv)}}
      end

      test "#{name} testnet r/s/v matches the Python SDK" do
        assert Action.sign_json(
                 @priv_key,
                 unquote(json),
                 unquote(nonce),
                 unquote(vault),
                 unquote(expires),
                 false
               ) == {:ok, %{r: unquote(tr), s: unquote(ts), v: unquote(tv)}}
      end
    end
  end

  describe "canonical key order (H3)" do
    # Decoding the canonical JSON into plain Elixir maps destroys key order
    # (BEAM map iteration order is not insertion order). `Action.ordered/1` has
    # to put it back, byte for byte, or the hash above is unreachable from the
    # action builders.
    for {name, json, _nonce, _vault, _expires, ordered, _hash, _m, _t} <- @l1_vectors,
        ordered do
      test "#{name} survives a scrambled round-trip through Action.ordered/1" do
        assert unquote(json)
               |> Jason.decode!()
               |> Action.ordered()
               |> Jason.encode!() == unquote(json)
      end
    end

    test "every action module's declared type has a canonical key order" do
      module_types =
        Path.wildcard(Path.expand("../lib/hyperliquid/api/exchange/*.ex", __DIR__))
        |> Enum.flat_map(fn path ->
          Regex.scan(~r/(?:\\{:type,\\s*|type:\\s*)"([a-zA-Z0-9]+)"/, File.read!(path))
        end)
        |> Enum.map(fn [_, type] -> type end)
        |> Enum.uniq()

      # Deploy/validator actions are tagged unions whose shape is chosen by the
      # caller; they build their own `Jason.OrderedObject` explicitly.
      unions =
        ~w(perpDeploy spotDeploy outcomeDeploy userOutcome cSignerAction cValidatorAction
           delegate undelegate changeSigner editValidator)

      eip712_primitives = ~w(string bool address bytes bytes32 uint8 uint64 uint256)

      missing =
        module_types
        |> Enum.reject(&(&1 in unions or &1 in eip712_primitives))
        |> Enum.reject(&(Action.key_order(&1) != nil))

      assert missing == [],
             "actions without a declared key order: #{inspect(missing)}"
    end
  end

  describe "user-signed actions (EIP-712 typed data)" do
    for {name, primary_type, domain, types, message, {r, s, v}} <- @user_signed_vectors do
      test "#{name} matches the Python SDK" do
        sig =
          Signer.sign_typed_data(
            @priv_key,
            unquote(domain),
            unquote(types),
            unquote(message),
            unquote(primary_type)
          )

        assert Map.take(sig, ["r", "s", "v"]) == %{
                 "r" => unquote(r),
                 "s" => unquote(s),
                 "v" => unquote(v)
               }
      end
    end
  end
end
''')
out.close()
print("written")
