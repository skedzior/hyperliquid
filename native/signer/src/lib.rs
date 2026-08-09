use std::str::FromStr;

use alloy::dyn_abi::Eip712Domain;
use alloy::primitives::{keccak256, Address, Signature as AlloySignature, B256};
use alloy::signers::{local::PrivateKeySigner, SignerSync};
use alloy::sol_types::{eip712_domain, SolStruct, SolValue};
use rustler::{Env, NifResult, Term, Encoder};
use serde_json::Value as JsonValue;
// For generic EIP-712 TypedData support
use ethers_core::types::transaction::eip712::{TypedData as EthersTypedData, Eip712 as _};
use serde::{Deserialize, Serialize};

// ===== Errors =====
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("wallet error: {0}")]
    Wallet(String),
    #[error("parse error: {0}")]
    GenericParse(String),
    #[error("json parse error: {0}")]
    JsonParse(String),
    #[error("rmp parse error: {0}")]
    RmpParse(String),
    #[error("signature failure: {0}")]
    SignatureFailure(String),
}

// EIP-712 for multi-sig send
#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SendMultiSig { pub signature_chain_id: u64, pub hyperliquid_chain: String, pub multi_sig_action_hash: B256, pub nonce: u64 }

impl Eip712 for SendMultiSig {
    fn domain(&self) -> Eip712Domain { tx_domain(self.signature_chain_id) }
    fn struct_hash(&self) -> B256 {
        let items = (
            keccak256("HyperliquidTransaction:SendMultiSig(string hyperliquidChain,bytes32 multiSigActionHash,uint64 nonce)"),
            keccak256(&self.hyperliquid_chain),
            &self.multi_sig_action_hash,
            &self.nonce,
        );
        keccak256(items.abi_encode())
    }
}

// Deterministic representation of MultiSig action for msgpack hashing
#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct MsSignature { r: String, s: String, v: u8 }

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct MsPayloadAction { #[serde(rename = "type")] type_field: String, time: u64 }

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct MsPayload { multi_sig_user: String, outer_signer: String, action: MsPayloadAction }

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct MsAction { signature_chain_id: String, signatures: Vec<MsSignature>, payload: MsPayload }

fn hash_ms_action_with_exp(
    action: &MsAction,
    timestamp: u64,
    vault_address: Option<Address>,
    expires_after: Option<u64>,
) -> Result<B256, Error> {
    let mut bytes = rmp_serde::to_vec_named(action).map_err(|e| Error::RmpParse(e.to_string()))?;
    bytes.extend(timestamp.to_be_bytes());
    if let Some(vault_address) = vault_address {
        bytes.push(1);
        bytes.extend(vault_address);
    } else {
        bytes.push(0);
    }
    if let Some(exp) = expires_after {
        bytes.push(0);
        bytes.extend(exp.to_be_bytes());
    }
    Ok(keccak256(bytes))
}

// New: Multi-sig variant that accepts arbitrary JSON action body (not constrained to Actions enum)
#[rustler::nif]
fn sign_multi_sig_action_ex<'a>(
    env: Env<'a>,
    private_key_hex: String,
    action_json: String,
    nonce: u64,
    is_mainnet: bool,
    vault_address: Option<String>,
    expires_after: Option<u64>,
) -> NifResult<Term<'a>> {
    let wallet = parse_wallet(&private_key_hex)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;

    let value: JsonValue = serde_json::from_str(&action_json)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let vault = parse_optional_address(vault_address)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;

    // Parse signatureChainId (hex string like "0x66eee") from JSON map
    let sig_chain_id = match &value {
        JsonValue::Object(map) => {
            match map.get("signatureChainId") {
                Some(JsonValue::String(s)) if s.starts_with("0x") || s.starts_with("0X") => {
                    u64::from_str_radix(&s[2..], 16)
                        .map_err(|e| rustler::Error::Term(Box::new(format!("invalid signatureChainId: {}", e))))?
                }
                Some(JsonValue::Number(n)) => n.as_u64().ok_or_else(|| rustler::Error::Term(Box::new("invalid signatureChainId number".to_string())))?,
                _ => return Err(rustler::Error::Term(Box::new("missing signatureChainId".to_string())))
            }
        }
        _ => return Err(rustler::Error::Term(Box::new("action must be a JSON object".to_string())))
    };

    // Compute multiSigActionHash over the full action object (no top-level type expected)
    let ms_hash = hash_json_value_with_exp(&value, nonce, vault, expires_after)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;

    // Build typed EIP-712 payload and sign
    let hyperliquid_chain = if is_mainnet { "Mainnet".to_string() } else { "Testnet".to_string() };
    let payload = SendMultiSig { signature_chain_id: sig_chain_id, hyperliquid_chain, multi_sig_action_hash: ms_hash, nonce };

    let sig = sign_typed_data(&payload, &wallet)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;

    signature_to_map(env, sig, None)
}

// Generic EIP-712 TypedData signer. Accepts JSON strings for domain/types/message and the primary type.
#[rustler::nif]
fn sign_typed_data<'a>(
    env: Env<'a>,
    private_key_hex: String,
    domain_json: String,
    types_json: String,
    message_json: String,
    primary_type: String,
) -> NifResult<Term<'a>> {
    let wallet = parse_wallet(&private_key_hex)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;

    let domain_val: JsonValue = serde_json::from_str(&domain_json)
        .map_err(|e| rustler::Error::Term(Box::new(format!("domain parse error: {}", e))))?;
    let types_val: JsonValue = serde_json::from_str(&types_json)
        .map_err(|e| rustler::Error::Term(Box::new(format!("types parse error: {}", e))))?;
    let message_val: JsonValue = serde_json::from_str(&message_json)
        .map_err(|e| rustler::Error::Term(Box::new(format!("message parse error: {}", e))))?;

    let mut root = serde_json::Map::new();
    root.insert("domain".to_string(), domain_val);
    root.insert("types".to_string(), types_val);
    root.insert("message".to_string(), message_val);
    root.insert("primaryType".to_string(), JsonValue::String(primary_type));

    let typed: EthersTypedData = serde_json::from_value(JsonValue::Object(root))
        .map_err(|e| rustler::Error::Term(Box::new(format!("typed data error: {}", e))))?;

    let digest = typed
        .encode_eip712()
        .map_err(|e| rustler::Error::Term(Box::new(format!("eip712 encode error: {}", e))))?;

    // Convert the digest [u8;32] to B256 for alloy signer
    let hash_b256 = B256::from(digest);

    let sig = wallet
        .sign_hash_sync(&hash_b256)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;

    signature_to_map(env, sig, None)
}

// ===== EIP712 core trait =====
trait Eip712 {
    fn domain(&self) -> Eip712Domain;
    fn struct_hash(&self) -> B256;
    fn eip712_signing_hash(&self) -> B256 {
        let mut digest_input = [0u8; 2 + 32 + 32];
        digest_input[0] = 0x19;
        digest_input[1] = 0x01;
        digest_input[2..34].copy_from_slice(&self.domain().hash_struct()[..]);
        digest_input[34..66].copy_from_slice(&self.struct_hash()[..]);
        keccak256(digest_input)
    }
}

// ===== L1 Agent typed struct (for L1 action signing) =====
mod l1_agent {
    use super::*;
    alloy::sol! {
        #[derive(Debug)]
        struct Agent {
            string source;
            bytes32 connectionId;
        }
    }

    impl super::Eip712 for Agent {
        fn domain(&self) -> Eip712Domain {
            eip712_domain! {
                name: "Exchange",
                version: "1",
                chain_id: 1337u64,
                verifying_contract: Address::ZERO,
            }
        }
        fn struct_hash(&self) -> B256 { self.eip712_hash_struct() }
    }

    pub(super) use Agent as L1Agent;
}

fn sign_typed_data<T: Eip712>(payload: &T, wallet: &PrivateKeySigner) -> Result<AlloySignature, Error> {
    wallet
        .sign_hash_sync(&payload.eip712_signing_hash())
        .map_err(|e| Error::SignatureFailure(e.to_string()))
}

fn sign_l1_agent_action(wallet: &PrivateKeySigner, connection_id: B256, is_mainnet: bool) -> Result<AlloySignature, Error> {
    let source = if is_mainnet { "a" } else { "b" }.to_string();
    let payload = l1_agent::L1Agent { source, connectionId: connection_id };
    sign_typed_data(&payload, wallet)
}

fn signature_to_map<'a>(env: Env<'a>, sig: AlloySignature, connection_id: Option<B256>) -> NifResult<Term<'a>> {
    // Zero-pad r and s to 64 hex chars (32 bytes) to match expected format
    let r = format!("0x{:064x}", sig.r());
    let s = format!("0x{:064x}", sig.s());
    let v = 27u64 + sig.v() as u64;
    let sig_hex = sig.to_string();

    let mut map = rustler::types::map::map_new(env);

    map = map
        .map_put("signature".encode(env), sig_hex.encode(env))
        .map_err(|_| rustler::Error::Term(Box::new("failed to encode map value")))?;
    map = map
        .map_put("r".encode(env), r.encode(env))
        .map_err(|_| rustler::Error::Term(Box::new("failed to encode map value")))?;
    map = map
        .map_put("s".encode(env), s.encode(env))
        .map_err(|_| rustler::Error::Term(Box::new("failed to encode map value")))?;
    map = map
        .map_put("v".encode(env), v.encode(env))
        .map_err(|_| rustler::Error::Term(Box::new("failed to encode map value")))?;

    if let Some(cid) = connection_id {
        let cid_str = format!("{:#x}", cid);
        map = map
            .map_put("connection_id".encode(env), cid_str.encode(env))
            .map_err(|_| rustler::Error::Term(Box::new("failed to encode map value")))?;
    }

    Ok(map)
}

fn parse_wallet(priv_key_hex: &str) -> Result<PrivateKeySigner, Error> {
    priv_key_hex
        .parse::<PrivateKeySigner>()
        .map_err(|e| Error::Wallet(e.to_string()))
}

fn parse_optional_address(addr_opt: Option<String>) -> Result<Option<Address>, Error> {
    if let Some(addr_str) = addr_opt {
        let a = Address::from_str(&addr_str)
            .map_err(|e| Error::GenericParse(format!("invalid address: {e}")))?;
        Ok(Some(a))
    } else {
        Ok(None)
    }
}

fn hash_action_with_exp(
    action: &Actions,
    timestamp: u64,
    vault_address: Option<Address>,
    expires_after: Option<u64>,
) -> Result<B256, Error> {
    let mut bytes = rmp_serde::to_vec_named(action).map_err(|e| Error::RmpParse(e.to_string()))?;
    // nonce (timestamp) big-endian u64
    bytes.extend(timestamp.to_be_bytes());
    // vault flag + address bytes if present
    if let Some(vault_address) = vault_address {
        bytes.push(1);
        bytes.extend(vault_address);
    } else {
        bytes.push(0);
    }
    // expiresAfter marker + value when present
    if let Some(exp) = expires_after {
        bytes.push(0);
        bytes.extend(exp.to_be_bytes());
    }
    Ok(keccak256(bytes))
}

fn hash_action(action: &Actions, timestamp: u64, vault_address: Option<Address>) -> Result<B256, Error> {
    hash_action_with_exp(action, timestamp, vault_address, None)
}

fn hash_json_value_with_exp(
    value: &JsonValue,
    timestamp: u64,
    vault_address: Option<Address>,
    expires_after: Option<u64>,
) -> Result<B256, Error> {
    let mut bytes = rmp_serde::to_vec_named(value).map_err(|e| Error::RmpParse(e.to_string()))?;
    // nonce (timestamp) big-endian u64
    bytes.extend(timestamp.to_be_bytes());
    // vault flag + address bytes if present
    if let Some(vault_address) = vault_address {
        bytes.push(1);
        bytes.extend(vault_address);
    } else {
        bytes.push(0);
    }
    // expiresAfter marker + value when present
    if let Some(exp) = expires_after {
        bytes.push(0);
        bytes.extend(exp.to_be_bytes());
    }
    Ok(keccak256(bytes))
}

// ===== Exchange action data (subset needed for signing) =====

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Limit { pub tif: String }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Trigger { pub is_market: bool, pub trigger_px: String, pub tpsl: String }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub enum Order { Limit(Limit), Trigger(Trigger) }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct OrderRequest {
    #[serde(rename = "a", alias = "asset")] pub asset: u32,
    #[serde(rename = "b", alias = "isBuy")] pub is_buy: bool,
    #[serde(rename = "p", alias = "limitPx")] pub limit_px: String,
    #[serde(rename = "s", alias = "sz")] pub sz: String,
    #[serde(rename = "r", alias = "reduceOnly", default)] pub reduce_only: bool,
    #[serde(rename = "t", alias = "orderType")] pub order_type: Order,
    #[serde(rename = "c", alias = "cloid", skip_serializing_if = "Option::is_none")] pub cloid: Option<String>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct BuilderInfo { #[serde(rename = "b")] pub builder: String, #[serde(rename = "f")] pub fee: u64 }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct BulkOrder { pub orders: Vec<OrderRequest>, pub grouping: String, #[serde(default, skip_serializing_if = "Option::is_none")] pub builder: Option<BuilderInfo> }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct CancelRequest { #[serde(rename = "a", alias = "asset")] pub asset: u32, #[serde(rename = "o", alias = "oid")] pub oid: u64 }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct BulkCancel { pub cancels: Vec<CancelRequest> }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct CancelRequestCloid { pub asset: u32, pub cloid: String }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct BulkCancelCloid { pub cancels: Vec<CancelRequestCloid> }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ModifyRequest { #[serde(rename = "o", alias = "oid")] pub oid: u64, pub order: OrderRequest }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct BulkModify { pub modifies: Vec<ModifyRequest> }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct UpdateLeverage { pub asset: u32, pub is_cross: bool, pub leverage: u32 }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct UpdateIsolatedMargin { pub asset: u32, pub is_buy: bool, pub ntli: i64 }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ClassTransfer { pub usdc: u64, pub to_perp: bool }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SpotUser { pub class_transfer: ClassTransfer }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct VaultTransfer { pub vault_address: Address, pub is_deposit: bool, pub usd: u64 }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SubAccountTransfer { pub sub_account_user: String, pub is_deposit: bool, pub usd: u64 }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SubAccountSpotTransfer { pub sub_account_user: String, pub is_deposit: bool, pub token: String, pub amount: String }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct UsdClassTransfer { pub signature_chain_id: String, pub hyperliquid_chain: String, pub amount: String, pub to_perp: bool, pub nonce: u64 }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SetReferrer { pub code: String }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct EvmUserModify { pub using_big_blocks: bool }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ScheduleCancel { #[serde(skip_serializing_if = "Option::is_none")] pub time: Option<u64> }

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ClaimRewards;

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(tag = "type")]
#[serde(rename_all = "camelCase")]
pub enum Actions {
    UpdateLeverage(UpdateLeverage),
    UpdateIsolatedMargin(UpdateIsolatedMargin),
    Order(BulkOrder),
    Cancel(BulkCancel),
    CancelByCloid(BulkCancelCloid),
    BatchModify(BulkModify),
    SpotUser(SpotUser),
    VaultTransfer(VaultTransfer),
    SubAccountTransfer(SubAccountTransfer),
    SubAccountSpotTransfer(SubAccountSpotTransfer),
    UsdClassTransfer(UsdClassTransfer),
    SetReferrer(SetReferrer),
    EvmUserModify(EvmUserModify),
    ScheduleCancel(ScheduleCancel),
    ClaimRewards(ClaimRewards),
}

// ===== EIP-712 typed payloads =====

fn tx_domain(chain_id: u64) -> Eip712Domain {
    eip712_domain! {
        name: "HyperliquidSignTransaction",
        version: "1",
        chain_id: chain_id,
        verifying_contract: Address::ZERO,
    }
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct UsdSend { pub signature_chain_id: u64, pub hyperliquid_chain: String, pub destination: String, pub amount: String, pub time: u64 }

impl Eip712 for UsdSend {
    fn domain(&self) -> Eip712Domain { tx_domain(self.signature_chain_id) }
    fn struct_hash(&self) -> B256 {
        let items = (
            keccak256("HyperliquidTransaction:UsdSend(string hyperliquidChain,string destination,string amount,uint64 time)"),
            keccak256(&self.hyperliquid_chain),
            keccak256(&self.destination),
            keccak256(&self.amount),
            &self.time,
        );
        keccak256(items.abi_encode())
    }
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Withdraw3 { pub signature_chain_id: u64, pub hyperliquid_chain: String, pub destination: String, pub amount: String, pub time: u64 }

impl Eip712 for Withdraw3 {
    fn domain(&self) -> Eip712Domain { tx_domain(self.signature_chain_id) }
    fn struct_hash(&self) -> B256 {
        let items = (
            keccak256("HyperliquidTransaction:Withdraw(string hyperliquidChain,string destination,string amount,uint64 time)"),
            keccak256(&self.hyperliquid_chain),
            keccak256(&self.destination),
            keccak256(&self.amount),
            &self.time,
        );
        keccak256(items.abi_encode())
    }
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SpotSend { pub signature_chain_id: u64, pub hyperliquid_chain: String, pub destination: String, pub token: String, pub amount: String, pub time: u64 }

impl Eip712 for SpotSend {
    fn domain(&self) -> Eip712Domain { tx_domain(self.signature_chain_id) }
    fn struct_hash(&self) -> B256 {
        let items = (
            keccak256("HyperliquidTransaction:SpotSend(string hyperliquidChain,string destination,string token,string amount,uint64 time)"),
            keccak256(&self.hyperliquid_chain),
            keccak256(&self.destination),
            keccak256(&self.token),
            keccak256(&self.amount),
            &self.time,
        );
        keccak256(items.abi_encode())
    }
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ApproveBuilderFee { pub signature_chain_id: u64, pub hyperliquid_chain: String, pub builder: Address, pub max_fee_rate: String, pub nonce: u64 }

impl Eip712 for ApproveBuilderFee {
    fn domain(&self) -> Eip712Domain { tx_domain(self.signature_chain_id) }
    fn struct_hash(&self) -> B256 {
        let items = (
            keccak256("HyperliquidTransaction:ApproveBuilderFee(string hyperliquidChain,string maxFeeRate,address builder,uint64 nonce)"),
            keccak256(&self.hyperliquid_chain),
            keccak256(&self.max_fee_rate),
            &self.builder,
            &self.nonce,
        );
        keccak256(items.abi_encode())
    }
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ApproveAgent { pub signature_chain_id: u64, pub hyperliquid_chain: String, pub agent_address: Address, pub agent_name: Option<String>, pub nonce: u64 }

impl Eip712 for ApproveAgent {
    fn domain(&self) -> Eip712Domain { tx_domain(self.signature_chain_id) }
    fn struct_hash(&self) -> B256 {
        let items = (
            keccak256("HyperliquidTransaction:ApproveAgent(string hyperliquidChain,address agentAddress,string agentName,uint64 nonce)"),
            keccak256(&self.hyperliquid_chain),
            &self.agent_address,
            keccak256(self.agent_name.as_deref().unwrap_or("")),
            &self.nonce,
        );
        keccak256(items.abi_encode())
    }
}

#[rustler::nif]
fn compute_connection_id(action_json: String, nonce: u64, vault_address: Option<String>) -> NifResult<String> {
    let action: Actions = serde_json::from_str(&action_json)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let vault = parse_optional_address(vault_address)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let cid = hash_action(&action, nonce, vault)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    Ok(format!("{:#x}", cid))
}

// New: expiresAfter-aware variant
#[rustler::nif]
fn compute_connection_id_ex(
    action_json: String,
    nonce: u64,
    vault_address: Option<String>,
    expires_after: Option<u64>,
) -> NifResult<String> {
    // Use generic JSON hashing that works with any action type
    let value: JsonValue = serde_json::from_str(&action_json)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let vault = parse_optional_address(vault_address)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let cid = hash_json_value_with_exp(&value, nonce, vault, expires_after)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    Ok(format!("{:#x}", cid))
}

#[rustler::nif]
fn sign_exchange_action<'a>(env: Env<'a>, private_key_hex: String, action_json: String, nonce: u64, is_mainnet: bool, vault_address: Option<String>) -> NifResult<Term<'a>> {
    let wallet = parse_wallet(&private_key_hex)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let action: Actions = serde_json::from_str(&action_json)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let vault = parse_optional_address(vault_address)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;

    let cid = hash_action(&action, nonce, vault)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;

    let sig = sign_l1_agent_action(&wallet, cid, is_mainnet)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;

    signature_to_map(env, sig, Some(cid))
}

// New: expiresAfter-aware variant
#[rustler::nif]
fn sign_exchange_action_ex<'a>(
    env: Env<'a>,
    private_key_hex: String,
    action_json: String,
    nonce: u64,
    is_mainnet: bool,
    vault_address: Option<String>,
    expires_after: Option<u64>,
) -> NifResult<Term<'a>> {
    let wallet = parse_wallet(&private_key_hex)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let action: Actions = serde_json::from_str(&action_json)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let vault = parse_optional_address(vault_address)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;

    let cid = hash_action_with_exp(&action, nonce, vault, expires_after)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;

    let sig = sign_l1_agent_action(&wallet, cid, is_mainnet)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;

    signature_to_map(env, sig, Some(cid))
}

fn chain(is_mainnet: bool) -> (u64, String) {
    // Hyperliquid uses chainId 42161 (Arbitrum One) for BOTH mainnet and testnet.
    // The network distinction is conveyed via the hyperliquidChain field.
    let chain_id = 42161u64;
    let hyperliquid_chain = if is_mainnet { "Mainnet" } else { "Testnet" }.to_string();
    (chain_id, hyperliquid_chain)
}

#[rustler::nif]
fn sign_usd_send<'a>(env: Env<'a>, private_key_hex: String, destination: String, amount: String, time: u64, is_mainnet: bool) -> NifResult<Term<'a>> {
    let wallet = parse_wallet(&private_key_hex)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let (signature_chain_id, hyperliquid_chain) = chain(is_mainnet);
    let payload = UsdSend { signature_chain_id, hyperliquid_chain, destination, amount, time };
    let sig = sign_typed_data(&payload, &wallet)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    signature_to_map(env, sig, None)
}

#[rustler::nif]
fn sign_withdraw3<'a>(env: Env<'a>, private_key_hex: String, destination: String, amount: String, time: u64, is_mainnet: bool) -> NifResult<Term<'a>> {
    let wallet = parse_wallet(&private_key_hex)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let (signature_chain_id, hyperliquid_chain) = chain(is_mainnet);
    let payload = Withdraw3 { signature_chain_id, hyperliquid_chain, destination, amount, time };
    let sig = sign_typed_data(&payload, &wallet)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    signature_to_map(env, sig, None)
}

#[rustler::nif]
fn sign_spot_send<'a>(env: Env<'a>, private_key_hex: String, destination: String, token: String, amount: String, time: u64, is_mainnet: bool) -> NifResult<Term<'a>> {
    let wallet = parse_wallet(&private_key_hex)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let (signature_chain_id, hyperliquid_chain) = chain(is_mainnet);
    let payload = SpotSend { signature_chain_id, hyperliquid_chain, destination, token, amount, time };
    let sig = sign_typed_data(&payload, &wallet)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    signature_to_map(env, sig, None)
}

#[rustler::nif]
fn sign_approve_builder_fee<'a>(env: Env<'a>, private_key_hex: String, builder: String, max_fee_rate: String, nonce: u64, is_mainnet: bool) -> NifResult<Term<'a>> {
    let wallet = parse_wallet(&private_key_hex)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let (signature_chain_id, hyperliquid_chain) = chain(is_mainnet);
    let builder_addr = Address::from_str(&builder)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let payload = ApproveBuilderFee { signature_chain_id, hyperliquid_chain, builder: builder_addr, max_fee_rate, nonce };
    let sig = sign_typed_data(&payload, &wallet)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    signature_to_map(env, sig, None)
}

#[rustler::nif]
fn sign_approve_agent<'a>(env: Env<'a>, private_key_hex: String, agent_address: String, agent_name: Option<String>, nonce: u64, is_mainnet: bool) -> NifResult<Term<'a>> {
    let wallet = parse_wallet(&private_key_hex)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let (signature_chain_id, hyperliquid_chain) = chain(is_mainnet);
    let agent_addr = Address::from_str(&agent_address)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    let payload = ApproveAgent { signature_chain_id, hyperliquid_chain, agent_address: agent_addr, agent_name, nonce };
    let sig = sign_typed_data(&payload, &wallet)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    signature_to_map(env, sig, None)
}

// Sign an L1 action with the given private key and connection ID
#[rustler::nif]
fn sign_l1_action<'a>(env: Env<'a>, private_key_hex: String, connection_id: String, is_mainnet: bool) -> NifResult<Term<'a>> {
    // Parse the wallet from private key
    let wallet = parse_wallet(&private_key_hex)
        .map_err(|e| rustler::Error::Term(Box::new(format!("wallet error: {}", e))))?;
    
    // Parse the connection ID as a B256 hash
    let cid = B256::from_str(&connection_id)
        .map_err(|e| rustler::Error::Term(Box::new(format!("invalid connection_id: {}", e))))?;
    
    // Sign the L1 action
    let sig = sign_l1_agent_action(&wallet, cid, is_mainnet)
        .map_err(|e| rustler::Error::Term(Box::new(format!("signing failed: {}", e))))?;

    // Convert the signature to a map and return
    signature_to_map(env, sig, Some(cid))
}

#[rustler::nif]
fn to_checksum_address(address: String) -> NifResult<String> {
    // Strip 0x/0X and whitespace
    let raw = address.trim().trim_start_matches("0x").trim_start_matches("0X").to_string();

    // Basic validation: 40 hex chars
    if raw.len() != 40 || !raw.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(rustler::Error::Term(Box::new(
            "invalid address; expected 40 hex chars (with or without 0x)".to_string(),
        )));
    }

    // EIP-55: use lowercase address when hashing
    let lower = raw.to_lowercase();

    // Keccak-256 over the ASCII hex characters
    let hash_b256 = keccak256(lower.as_bytes());
    let hash_hex = format!("{:x}", hash_b256); // 64-char hex

    // Build checksummed string
    let mut out = String::with_capacity(42);
    out.push_str("0x");

    for (i, ch) in lower.chars().enumerate() {
        // For each address nibble, check corresponding hash nibble
        let nibble = u8::from_str_radix(&hash_hex[i..i + 1], 16).unwrap();
        if nibble >= 8 {
            out.push(ch.to_ascii_uppercase());
        } else {
            out.push(ch);
        }
    }

    Ok(out)
}

#[rustler::nif]
fn derive_address(private_key_hex: String) -> NifResult<String> {
    let wallet = parse_wallet(&private_key_hex)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    Ok(format!("{}", wallet.address()))
}

// rustler 0.38 dropped the explicit NIF list from init!/2 — every function
// carrying #[rustler::nif] is registered automatically.
rustler::init!("Elixir.Hyperliquid.Signer");
