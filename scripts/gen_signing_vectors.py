"""Generate cross-SDK signing vectors for the Elixir SDK from hyperliquid-python-sdk.

Every vector below is produced by an independent implementation (the official
Python SDK: its own msgpack encoder, its own keccak, its own eth_account
secp256k1 signer). None of it comes from the Elixir library, so the vectors are
an oracle for both the msgpack key order (H3) and the signing path (H2).

Usage
-----

    # in a venv with the python SDK installed and msgpack >= 1.0 (str8 encoding!)
    python scripts/gen_signing_vectors.py vectors.json
    python scripts/emit_signing_vectors_test.py vectors.json test/signing_vectors_test.exs
    mix format test/signing_vectors_test.exs   # the emitter writes unformatted code

Point HL_PYTHON_SDK at a hyperliquid-python-sdk checkout if it is not importable.
"""

import json
import os
import sys

sdk = os.environ.get("HL_PYTHON_SDK")
if sdk:
    sys.path.insert(0, sdk)

import eth_account
from hyperliquid.utils.signing import (
    action_hash,
    sign_inner,
    sign_l1_action,
    user_signed_payload,
    USD_SEND_SIGN_TYPES,
    SPOT_TRANSFER_SIGN_TYPES,
    WITHDRAW_SIGN_TYPES,
    USD_CLASS_TRANSFER_SIGN_TYPES,
    TOKEN_DELEGATE_TYPES,
    USER_DEX_ABSTRACTION_SIGN_TYPES,
    CONVERT_TO_MULTI_SIG_USER_SIGN_TYPES,
    SEND_ASSET_SIGN_TYPES,
)
from eth_utils import to_hex

PK = "0x0123456789012345678901234567890123456789012345678901234567890123"
NKTKAS_PK = "0x822e9959e022b78423eb653a62ea0020cd283e71a2a8133a6ff2aeffaf373cff"
W = eth_account.Account.from_key(PK)
VAULT = "0x1719884eb866cb12b2287399b15f7db5e7d775ea"
ADDR = "0x1d9470d4b963f552e6f671a81619d395877bf409"
CLOID = "0x00000000000000000000000000000001"

LIMIT_ORDER = {"a": 1, "b": True, "p": "100", "s": "100", "r": False, "t": {"limit": {"tif": "Gtc"}}}
TRIGGER_ORDER = {
    "a": 1,
    "b": True,
    "p": "100",
    "s": "100",
    "r": False,
    "t": {"trigger": {"isMarket": True, "triggerPx": "103", "tpsl": "sl"}},
}
CLOID_ORDER = dict(LIMIT_ORDER, **{"c": CLOID})

# name, action (in canonical Hyperliquid key order), nonce, vault, expires_after,
# whether the action type has a declared key order in Elixir's Action module.
L1 = [
    ("order_limit_gtc", {"type": "order", "orders": [LIMIT_ORDER], "grouping": "na"}, 0, None, None, True),
    ("order_with_cloid", {"type": "order", "orders": [CLOID_ORDER], "grouping": "na"}, 0, None, None, True),
    ("order_trigger_tpsl", {"type": "order", "orders": [TRIGGER_ORDER], "grouping": "na"}, 0, None, None, True),
    ("order_grouping_priority",
     {"type": "order", "orders": [LIMIT_ORDER], "grouping": {"p": 50000000}}, 1234567890, None, None, True),
    ("order_with_builder",
     {"type": "order", "orders": [LIMIT_ORDER], "grouping": "na",
      "builder": {"b": ADDR, "f": 10}}, 1234567890, None, None, True),
    ("order_with_vault_and_expires",
     {"type": "order", "orders": [LIMIT_ORDER], "grouping": "na"}, 1234567890, VAULT, 1234567890, True),
    ("cancel", {"type": "cancel", "cancels": [{"a": 1, "o": 12345}]}, 1234567890, None, None, True),
    ("cancel_by_cloid",
     {"type": "cancelByCloid", "cancels": [{"asset": 1, "cloid": CLOID}]}, 1234567890, None, None, True),
    ("modify", {"type": "modify", "oid": 12345, "order": LIMIT_ORDER}, 1234567890, None, None, True),
    ("batch_modify",
     {"type": "batchModify", "modifies": [{"oid": 12345, "order": LIMIT_ORDER}]}, 1234567890, None, None, True),
    ("schedule_cancel_no_time", {"type": "scheduleCancel"}, 0, None, None, True),
    ("schedule_cancel_with_time", {"type": "scheduleCancel", "time": 123456789}, 0, None, None, True),
    ("update_leverage",
     {"type": "updateLeverage", "asset": 1, "isCross": True, "leverage": 10}, 1234567890, None, None, True),
    ("update_isolated_margin",
     {"type": "updateIsolatedMargin", "asset": 1, "isBuy": True, "ntli": 1000000}, 1234567890, None, None, True),
    ("create_sub_account", {"type": "createSubAccount", "name": "example"}, 0, None, None, True),
    ("sub_account_modify",
     {"type": "subAccountModify", "subAccountUser": ADDR, "name": "renamed"}, 1234567890, None, None, True),
    ("sub_account_transfer",
     {"type": "subAccountTransfer", "subAccountUser": ADDR, "isDeposit": True, "usd": 10}, 0, None, None, True),
    ("sub_account_spot_transfer",
     {"type": "subAccountSpotTransfer", "subAccountUser": ADDR, "isDeposit": True,
      "token": "USDC:0xeb62eee3685fc4c43992febcd9e75443", "amount": "50"}, 1234567890, None, None, True),
    ("spot_user", {"type": "spotUser", "toggleSpotDusting": {"optOut": False}}, 1234567890, None, None, True),
    ("create_vault",
     {"type": "createVault", "name": "example vault", "description": "a test vault for vectors",
      "initialUsd": 100000000, "nonce": 1234567890}, 1234567890, None, None, True),
    ("vault_transfer",
     {"type": "vaultTransfer", "vaultAddress": VAULT, "isDeposit": True, "usd": 1000000}, 1234567890, None, None, True),
    ("vault_modify",
     {"type": "vaultModify", "vaultAddress": VAULT, "allowDeposits": True,
      "alwaysCloseOnWithdraw": False}, 1234567890, None, None, True),
    ("vault_distribute",
     {"type": "vaultDistribute", "vaultAddress": VAULT, "usd": 1000000}, 1234567890, None, None, True),
    ("set_referrer", {"type": "setReferrer", "code": "TESTCODE"}, 1234567890, None, None, True),
    ("register_referrer", {"type": "registerReferrer", "code": "TESTCODE"}, 1234567890, None, None, True),
    ("claim_rewards", {"type": "claimRewards"}, 1234567890, None, None, True),
    ("evm_user_modify", {"type": "evmUserModify", "usingBigBlocks": True}, 1234567890, None, None, True),
    ("noop", {"type": "noop"}, 1234567890, None, None, True),
    ("set_display_name", {"type": "setDisplayName", "displayName": "vector"}, 1234567890, None, None, True),
    ("twap_order",
     {"type": "twapOrder", "twap": {"a": 1, "b": True, "s": "10", "r": False, "m": 30, "t": True}},
     1234567890, None, None, True),
    ("twap_cancel", {"type": "twapCancel", "a": 1, "t": 5}, 1234567890, None, None, True),
    ("reserve_request_weight",
     {"type": "reserveRequestWeight", "weight": 100}, 1234567890, None, None, True),
    ("validator_l1_stream",
     {"type": "validatorL1Stream", "riskFreeRate": "0.05"}, 1234567890, None, None, True),
    ("agent_set_abstraction",
     {"type": "agentSetAbstraction", "abstraction": "u"}, 1234567890, None, None, True),
    ("agent_enable_dex_abstraction",
     {"type": "agentEnableDexAbstraction"}, 1234567890, None, None, True),
    ("borrow_lend",
     {"type": "borrowLend", "operation": "borrow", "token": 0, "amount": "10"}, 1234567890, None, None, True),
    ("top_up_isolated_only_margin",
     {"type": "topUpIsolatedOnlyMargin", "asset": 1, "leverage": "5"}, 1234567890, None, None, True),
    ("hip3_liquidator_transfer",
     {"type": "hip3LiquidatorTransfer", "dex": "test", "ntl": 1000000, "isDeposit": True},
     1234567890, None, None, True),
    ("authorize_aqav2_role",
     {"type": "authorizeAqav2Role", "token": 0, "role": "deployer"}, 1234567890, None, None, True),
    ("finalize_evm_contract",
     {"type": "finalizeEvmContract", "token": 0, "input": {"create": {"nonce": 1}}},
     1234567890, None, None, True),
    ("gossip_priority_bid",
     {"type": "gossipPriorityBid", "slotId": 1, "ip": "1.2.3.4", "maxGas": 1000}, 1234567890, None, None, True),
    ("agent_send_asset",
     {"type": "agentSendAsset", "destination": ADDR, "sourceDex": "", "destinationDex": "spot",
      "token": "USDC:0xeb62eee3685fc4c43992febcd9e75443", "amount": "100", "fromSubAccount": "",
      "nonce": 1234567890}, 1234567890, None, None, True),
    ("usd_class_transfer_l1",
     {"type": "usdClassTransfer", "amount": "100", "toPerp": True}, 1234567890, None, None, True),
    # NOTE: userPortfolioMargin / userDexAbstraction / linkStakingUser /
    # convertToMultiSigUser used to be generated here as L1 vectors. They are
    # user-signed (EIP-712) actions in both nktkas and the Python SDK, so their
    # vectors now live in the US block below.
    ("activate_outcome_deployer",
     {"type": "activateOutcomeDeployer", "isDeactivate": False}, 1234567890, None, None, True),
]


def pad(h):
    return "0x" + h[2:].rjust(64, "0")


def sig(d):
    return {"r": pad(d["r"]), "s": pad(d["s"]), "v": d["v"]}


l1_out = []
for name, action, nonce, vault, expires, ordered in L1:
    entry = {
        "name": name,
        "json": json.dumps(action, separators=(",", ":")),
        "nonce": nonce,
        "vault": vault,
        "expires": expires,
        "ordered": ordered,
        "hash": to_hex(action_hash(action, vault, nonce, expires)),
        "mainnet": sig(sign_l1_action(W, action, vault, nonce, expires, True)),
        "testnet": sig(sign_l1_action(W, action, vault, nonce, expires, False)),
    }
    l1_out.append(entry)

# ---- user-signed (EIP-712) vectors -------------------------------------------------
# Signed through the generic typed-data path so the exact domain/types/message the
# Elixir SDK sends is what gets hashed.

def user_signed(name, primary_type, types, action, chain_id_hex):
    act = dict(action)
    act["signatureChainId"] = chain_id_hex
    payload = user_signed_payload(primary_type, types, act)
    s = sig(sign_inner(W, payload))
    return {
        "name": name,
        "primary_type": primary_type,
        "domain": json.dumps(payload["domain"], separators=(",", ":")),
        "types": json.dumps({primary_type: types}, separators=(",", ":")),
        "message": json.dumps(act, separators=(",", ":")),
        "signature": s,
    }


US = []
for chain_hex, suffix in (("0x66eee", "421614"), ("0xa4b1", "42161")):
    US.append(user_signed(
        "usd_send_" + suffix, "HyperliquidTransaction:UsdSend", USD_SEND_SIGN_TYPES,
        {"hyperliquidChain": "Mainnet", "destination": "0x5e9ee1089755c3435139848e47e6635505d5a13a",
         "amount": "1", "time": 1687816341423}, chain_hex))
    US.append(user_signed(
        "spot_send_" + suffix, "HyperliquidTransaction:SpotSend", SPOT_TRANSFER_SIGN_TYPES,
        {"hyperliquidChain": "Mainnet", "destination": "0x5e9ee1089755c3435139848e47e6635505d5a13a",
         "token": "USDC:0xeb62eee3685fc4c43992febcd9e75443", "amount": "1",
         "time": 1687816341423}, chain_hex))
    US.append(user_signed(
        "withdraw3_" + suffix, "HyperliquidTransaction:Withdraw", WITHDRAW_SIGN_TYPES,
        {"hyperliquidChain": "Mainnet", "destination": "0x5e9ee1089755c3435139848e47e6635505d5a13a",
         "amount": "1", "time": 1687816341423}, chain_hex))
    US.append(user_signed(
        "usd_class_transfer_" + suffix, "HyperliquidTransaction:UsdClassTransfer",
        USD_CLASS_TRANSFER_SIGN_TYPES,
        {"hyperliquidChain": "Mainnet", "amount": "100", "toPerp": True,
         "nonce": 1687816341423}, chain_hex))
    US.append(user_signed(
        "token_delegate_" + suffix, "HyperliquidTransaction:TokenDelegate", TOKEN_DELEGATE_TYPES,
        {"hyperliquidChain": "Mainnet", "validator": ADDR, "wei": 100000000,
         "isUndelegate": False, "nonce": 1687816341423}, chain_hex))
    US.append(user_signed(
        "approve_agent_" + suffix, "HyperliquidTransaction:ApproveAgent",
        [{"name": "hyperliquidChain", "type": "string"},
         {"name": "agentAddress", "type": "address"},
         {"name": "agentName", "type": "string"},
         {"name": "nonce", "type": "uint64"}],
        {"hyperliquidChain": "Mainnet", "agentAddress": ADDR, "agentName": "agent",
         "nonce": 1687816341423}, chain_hex))
    US.append(user_signed(
        "user_portfolio_margin_" + suffix, "HyperliquidTransaction:UserPortfolioMargin",
        # Not declared by the Python SDK; field list from @nktkas/hyperliquid
        # (UserPortfolioMarginTypes).
        [{"name": "hyperliquidChain", "type": "string"},
         {"name": "user", "type": "address"},
         {"name": "enabled", "type": "bool"},
         {"name": "nonce", "type": "uint64"}],
        {"hyperliquidChain": "Mainnet", "user": ADDR, "enabled": True,
         "nonce": 1687816341423}, chain_hex))
    US.append(user_signed(
        "user_dex_abstraction_" + suffix, "HyperliquidTransaction:UserDexAbstraction",
        USER_DEX_ABSTRACTION_SIGN_TYPES,
        {"hyperliquidChain": "Mainnet", "user": ADDR, "enabled": True,
         "nonce": 1687816341423}, chain_hex))
    US.append(user_signed(
        "link_staking_user_" + suffix, "HyperliquidTransaction:LinkStakingUser",
        # Not declared by the Python SDK; field list from @nktkas/hyperliquid
        # (LinkStakingUserTypes).
        [{"name": "hyperliquidChain", "type": "string"},
         {"name": "user", "type": "address"},
         {"name": "isFinalize", "type": "bool"},
         {"name": "nonce", "type": "uint64"}],
        {"hyperliquidChain": "Mainnet", "user": ADDR, "isFinalize": False,
         "nonce": 1687816341423}, chain_hex))
    US.append(user_signed(
        "convert_to_multi_sig_user_" + suffix, "HyperliquidTransaction:ConvertToMultiSigUser",
        CONVERT_TO_MULTI_SIG_USER_SIGN_TYPES,
        {"hyperliquidChain": "Mainnet",
         "signers": "{\"authorizedUsers\":[\"%s\"],\"threshold\":1}" % ADDR,
         "nonce": 1687816341423}, chain_hex))
    US.append(user_signed(
        "approve_builder_fee_" + suffix, "HyperliquidTransaction:ApproveBuilderFee",
        [{"name": "hyperliquidChain", "type": "string"},
         {"name": "maxFeeRate", "type": "string"},
         {"name": "builder", "type": "address"},
         {"name": "nonce", "type": "uint64"}],
        {"hyperliquidChain": "Mainnet", "maxFeeRate": "0.001%", "builder": ADDR,
         "nonce": 1687816341423}, chain_hex))
    US.append(user_signed(
        "c_deposit_" + suffix, "HyperliquidTransaction:CDeposit",
        # Not declared by the Python SDK; field list from @nktkas/hyperliquid (CDepositTypes).
        [{"name": "hyperliquidChain", "type": "string"},
         {"name": "wei", "type": "uint64"},
         {"name": "nonce", "type": "uint64"}],
        {"hyperliquidChain": "Mainnet", "wei": 100000000, "nonce": 1687816341423}, chain_hex))
    US.append(user_signed(
        "c_withdraw_" + suffix, "HyperliquidTransaction:CWithdraw",
        # Not declared by the Python SDK; field list from @nktkas/hyperliquid (CWithdrawTypes).
        [{"name": "hyperliquidChain", "type": "string"},
         {"name": "wei", "type": "uint64"},
         {"name": "nonce", "type": "uint64"}],
        {"hyperliquidChain": "Mainnet", "wei": 100000000, "nonce": 1687816341423}, chain_hex))
    US.append(user_signed(
        "send_asset_" + suffix, "HyperliquidTransaction:SendAsset", SEND_ASSET_SIGN_TYPES,
        {"hyperliquidChain": "Mainnet", "destination": "0x5e9ee1089755c3435139848e47e6635505d5a13a",
         "sourceDex": "", "destinationDex": "spot",
         "token": "USDC:0xeb62eee3685fc4c43992febcd9e75443", "amount": "100",
         "fromSubAccount": "", "nonce": 1687816341423}, chain_hex))
    US.append(user_signed(
        "staking_link_disable_trading_user_" + suffix,
        "HyperliquidTransaction:StakingLinkDisableTradingUser",
        # Not declared by the Python SDK; field list from @nktkas/hyperliquid
        # (StakingLinkDisableTradingUserTypes).
        [{"name": "hyperliquidChain", "type": "string"},
         {"name": "tradingUser", "type": "address"},
         {"name": "nonce", "type": "uint64"}],
        {"hyperliquidChain": "Mainnet", "tradingUser": ADDR, "nonce": 1687816341423}, chain_hex))
    US.append(user_signed(
        "user_set_abstraction_" + suffix, "HyperliquidTransaction:UserSetAbstraction",
        # Not declared by the Python SDK; field list from @nktkas/hyperliquid
        # (UserSetAbstractionTypes) — note the `user` field the Elixir module used to omit.
        [{"name": "hyperliquidChain", "type": "string"},
         {"name": "user", "type": "address"},
         {"name": "abstraction", "type": "string"},
         {"name": "nonce", "type": "uint64"}],
        {"hyperliquidChain": "Mainnet", "user": ADDR, "abstraction": "unifiedAccount",
         "nonce": 1687816341423}, chain_hex))
    US.append(user_signed(
        "send_to_evm_with_data_" + suffix, "HyperliquidTransaction:SendToEvmWithData",
        # Not declared by the Python SDK; field list from @nktkas/hyperliquid
        # (SendToEvmWithDataTypes) — `destinationChainId` is uint32 and `data` is bytes.
        [{"name": "hyperliquidChain", "type": "string"},
         {"name": "token", "type": "string"},
         {"name": "amount", "type": "string"},
         {"name": "sourceDex", "type": "string"},
         {"name": "destinationRecipient", "type": "string"},
         {"name": "addressEncoding", "type": "string"},
         {"name": "destinationChainId", "type": "uint32"},
         {"name": "gasLimit", "type": "uint64"},
         {"name": "data", "type": "bytes"},
         {"name": "nonce", "type": "uint64"}],
        {"hyperliquidChain": "Mainnet",
         "token": "USDC:0xeb62eee3685fc4c43992febcd9e75443", "amount": "100",
         "sourceDex": "", "destinationRecipient": ADDR, "addressEncoding": "hex",
         "destinationChainId": 999, "gasLimit": 200000, "data": "0xdeadbeef",
         "nonce": 1687816341423}, chain_hex))

json.dump({"private_key": PK, "l1": l1_out, "user_signed": US}, open(sys.argv[1], "w"), indent=1)
print("l1 vectors:", len(l1_out), "user-signed vectors:", len(US))
