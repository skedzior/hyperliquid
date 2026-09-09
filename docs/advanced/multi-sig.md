# Multi-Sig Actions

A multi-sig account (created with `Hyperliquid.Api.Exchange.ConvertToMultiSigUser`)
executes an action only when a quorum of authorized signers has signed it. Every
multi-sig request therefore carries two signature layers.

| Layer | Who signs | What is signed |
|-------|-----------|----------------|
| inner | each authorized signer | **L1 action:** `[multiSigUser, outerSigner, action]`, msgpack-hashed like a normal L1 action. **User-signed action:** the EIP-712 action with `payloadMultiSigUser` and `outerSigner` injected right after the primary type's first field. |
| outer | the leader (the first signer) | the assembled wrapper minus its `type` key, hashed as an L1 action, then signed as `HyperliquidTransaction:SendMultiSig` |

Inner signatures are **trimmed** (leading zeros stripped from `r` and `s`) before
being embedded; the outer signature is not.

Both hashes are msgpack over the action, so **key order is part of the hash** -
always build actions with `Jason.OrderedObject`, never a plain map.

## Usage

```elixir
{:ok, %{action: action, signature: sig, nonce: nonce}} =
  Hyperliquid.Api.MultiSig.sign_l1([leader_key, second_key],
    multi_sig_user: "0x...",
    action: Jason.OrderedObject.new([{"type", "cancel"}, {"cancels", []}])
  )

{:ok, resp} = Hyperliquid.Api.MultiSig.send(action, sig, nonce)
```

Sign-and-send in one step:

```elixir
Hyperliquid.multi_sig_l1(signers, multi_sig_user: "0x...", action: action)
Hyperliquid.multi_sig_user_signed(signers, multi_sig_user: "0x...", action: action)
```

## Inner vs Outer Action

`userSetAbstraction` is the only action whose wrapper payload differs from the
signed action: the payload uses single-letter abstraction codes.

| Long form (inner) | Payload code (outer) |
|-------------------|----------------------|
| `disabled` | `i` |
| `unifiedAccount` | `u` |
| `portfolioMargin` | `p` |

`Hyperliquid.Api.MultiSig.payload_action/1` applies that mapping automatically;
pass `:payload_action` to override it.

## API

`outer_signer/1`, `build_payload/3`, `build_user_signed_payload/4`,
`sign_payload/3`, `sign_user_signed_payload/3`, `build_action/5`,
`sign_action/3`, `send/3,4`, `sign_l1/2`, `sign_user_signed/2`, `request_l1/2`,
`request_user_signed/2`, `payload_action/1`, `trim_signature/1`.

`Hyperliquid.Api.MultiSig` is not an endpoint and is deliberately absent from
`Hyperliquid.Api.Registry` - it wraps other actions rather than being one.

## Known Caveat

`sign_l1/2` defaults `signature_chain_id` to `"0xa4b1"` (42161), this repo's
convention. `@nktkas/hyperliquid` requires it explicitly. If the exchange
validates it for multi-sig, a `Hyperliquid.Config`-driven default would be
safer.
