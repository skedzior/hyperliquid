defmodule Hyperliquid.Api.Exchange.Action do
  @moduledoc """
  Canonical key ordering and L1 signing for exchange actions.

  The msgpack action hash Hyperliquid signs is **order sensitive**: the
  validator deserializes the action into its own Rust struct and re-serializes
  it in that struct's declared field order before hashing, so the client has to
  emit the same order byte for byte.

  Every action therefore has to be encoded from an ordered representation
  (`Jason.OrderedObject`) rather than a plain Elixir map, whose iteration order
  is an implementation detail of the BEAM (literal order for small maps, hash
  order above 32 keys, and arbitrary for anything built with `Map.put/3`).

  `ordered/1` is the single place that knows the canonical field order for each
  action type. The orders are transcribed from `@nktkas/hyperliquid`'s valibot
  schemas (`src/api/exchange/_methods/*.ts`), which are the same orders the
  Python SDK's dict literals produce.

  Unknown keys (forward-compatibility seams such as the trailing-stop fields
  merged into a trigger order) are preserved and appended after the declared
  ones.
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Signer

  # ===================== Nested shapes =====================

  @limit {:object, [{"tif", nil}]}
  @trigger {:object, [{"isMarket", nil}, {"triggerPx", nil}, {"tpsl", nil}]}
  @order_type {:object, [{"limit", @limit}, {"trigger", @trigger}]}
  @builder {:object, [{"b", nil}, {"f", nil}]}
  @order_wire {:object,
               [
                 {"a", nil},
                 {"b", nil},
                 {"p", nil},
                 {"s", nil},
                 {"r", nil},
                 {"t", @order_type},
                 {"c", nil}
               ]}
  @modify_wire {:object, [{"oid", nil}, {"order", @order_wire}]}
  @twap_wire {:object, [{"a", nil}, {"b", nil}, {"s", nil}, {"r", nil}, {"m", nil}, {"t", nil}]}
  @twap_details {:object, [{"t", {:object, [{"p", nil}, {"a", nil}]}}, {"s", nil}]}

  @asset_request {:object,
                  [
                    {"coin", nil},
                    {"szDecimals", nil},
                    {"oraclePx", nil},
                    {"marginTableId", nil},
                    {"marginMode", nil},
                    {"onlyIsolated", nil}
                  ]}
  @deploy_schema {:object, [{"fullName", nil}, {"collateralToken", nil}, {"oracleUpdater", nil}]}
  @register_asset {:object,
                   [
                     {"maxGas", nil},
                     {"assetRequest", @asset_request},
                     {"dex", nil},
                     {"schema", @deploy_schema}
                   ]}
  @margin_table {:object,
                 [
                   {"description", nil},
                   {"marginTiers",
                    {:array, {:object, [{"lowerBound", nil}, {"maxLeverage", nil}]}}}
                 ]}

  # ===================== Action key order =====================
  #
  # Source: @nktkas/hyperliquid src/api/exchange/_methods/<action>.ts
  # (`action: v.object({ ... })` field order).

  @specs %{
    "activateOutcomeDeployer" => {:object, [{"type", nil}, {"isDeactivate", nil}]},
    "agentEnableDexAbstraction" => {:object, [{"type", nil}]},
    "agentSendAsset" =>
      {:object,
       [
         {"type", nil},
         {"destination", nil},
         {"sourceDex", nil},
         {"destinationDex", nil},
         {"token", nil},
         {"amount", nil},
         {"fromSubAccount", nil},
         {"nonce", nil}
       ]},
    "agentSetAbstraction" => {:object, [{"type", nil}, {"abstraction", nil}]},
    "approveAgent" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"agentAddress", nil},
         {"agentName", nil},
         {"nonce", nil}
       ]},
    "approveBuilderFee" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"maxFeeRate", nil},
         {"builder", nil},
         {"nonce", nil}
       ]},
    "authorizeAqav2Role" => {:object, [{"type", nil}, {"token", nil}, {"role", nil}]},
    "batchModify" => {:object, [{"type", nil}, {"modifies", {:array, @modify_wire}}, {"a", nil}]},
    "borrowLend" =>
      {:object, [{"type", nil}, {"operation", nil}, {"token", nil}, {"amount", nil}]},
    "cDeposit" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"wei", nil},
         {"nonce", nil}
       ]},
    "cWithdraw" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"wei", nil},
         {"nonce", nil}
       ]},
    "cancel" =>
      {:object,
       [
         {"type", nil},
         {"cancels", {:array, {:object, [{"a", nil}, {"o", nil}]}}},
         {"f", nil}
       ]},
    "cancelByCloid" =>
      {:object,
       [
         {"type", nil},
         {"cancels", {:array, {:object, [{"asset", nil}, {"cloid", nil}]}}},
         {"f", nil}
       ]},
    "claimRewards" => {:object, [{"type", nil}]},
    "convertToMultiSigUser" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"signers", nil},
         {"nonce", nil}
       ]},
    "createSubAccount" => {:object, [{"type", nil}, {"name", nil}]},
    "createVault" =>
      {:object,
       [
         {"type", nil},
         {"name", nil},
         {"description", nil},
         {"initialUsd", nil},
         {"nonce", nil}
       ]},
    "evmUserModify" => {:object, [{"type", nil}, {"usingBigBlocks", nil}]},
    "finalizeEvmContract" => {:object, [{"type", nil}, {"token", nil}, {"input", nil}]},
    "gossipPriorityBid" =>
      {:object, [{"type", nil}, {"slotId", nil}, {"ip", nil}, {"maxGas", nil}]},
    "hip3LiquidatorTransfer" =>
      {:object, [{"type", nil}, {"dex", nil}, {"ntl", nil}, {"isDeposit", nil}]},
    "linkStakingUser" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"user", nil},
         {"isFinalize", nil},
         {"nonce", nil}
       ]},
    "modify" => {:object, [{"type", nil}, {"oid", nil}, {"order", @order_wire}, {"a", nil}]},
    "noop" => {:object, [{"type", nil}]},
    "order" =>
      {:object,
       [
         {"type", nil},
         {"orders", {:array, @order_wire}},
         {"grouping", nil},
         {"builder", @builder}
       ]},
    "perpDeploy" =>
      {:object,
       [
         {"type", nil},
         {"registerAsset2", @register_asset},
         {"registerAsset", @register_asset},
         {"setOracle",
          {:object,
           [{"dex", nil}, {"oraclePxs", nil}, {"markPxs", nil}, {"externalPerpPxs", nil}]}},
         {"setFundingMultipliers", nil},
         {"setFundingInterestRates", nil},
         {"haltTrading", {:object, [{"coin", nil}, {"isHalted", nil}]}},
         {"setMarginTableIds", nil},
         {"insertMarginTable", {:object, [{"dex", nil}, {"marginTable", @margin_table}]}},
         {"setFeeRecipient", {:object, [{"dex", nil}, {"feeRecipient", nil}]}},
         {"setOpenInterestCaps", nil},
         {"setSubDeployers",
          {:object,
           [
             {"dex", nil},
             {"subDeployers",
              {:array, {:object, [{"variant", nil}, {"user", nil}, {"allowed", nil}]}}}
           ]}},
         {"setMarginModes", nil},
         {"setFeeScale", {:object, [{"dex", nil}, {"scale", nil}]}},
         {"setGrowthModes", nil},
         {"setDeployerFees", nil},
         {"setPerpAnnotation",
          {:object,
           [
             {"coin", nil},
             {"category", nil},
             {"description", nil},
             {"displayName", nil},
             {"keywords", nil}
           ]}},
         {"disableDex", nil}
       ]},
    "spotDeploy" =>
      {:object,
       [
         {"type", nil},
         {"registerToken2",
          {:object,
           [
             {"spec", {:object, [{"name", nil}, {"szDecimals", nil}, {"weiDecimals", nil}]}},
             {"maxGas", nil},
             {"fullName", nil}
           ]}},
         {"userGenesis",
          {:object,
           [
             {"token", nil},
             {"userAndWei", nil},
             {"existingTokenAndWei", nil},
             {"blacklistUsers", nil}
           ]}},
         {"genesis", {:object, [{"token", nil}, {"maxSupply", nil}, {"noHyperliquidity", nil}]}},
         {"registerSpot", {:object, [{"tokens", nil}]}},
         {"registerHyperliquidity",
          {:object,
           [
             {"spot", nil},
             {"startPx", nil},
             {"orderSz", nil},
             {"nOrders", nil},
             {"nSeededLevels", nil}
           ]}},
         {"setDeployerTradingFeeShare", {:object, [{"token", nil}, {"share", nil}]}},
         {"enableQuoteToken", {:object, [{"token", nil}]}},
         {"disableQuoteToken", {:object, [{"token", nil}]}},
         {"requestEvmContract",
          {:object, [{"token", nil}, {"address", nil}, {"evmExtraWeiDecimals", nil}]}},
         {"outcome", nil}
       ]},
    "registerReferrer" => {:object, [{"type", nil}, {"code", nil}]},
    "reserveRequestWeight" => {:object, [{"type", nil}, {"weight", nil}, {"destination", nil}]},
    "scheduleCancel" => {:object, [{"type", nil}, {"time", nil}]},
    "sendAsset" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"destination", nil},
         {"sourceDex", nil},
         {"destinationDex", nil},
         {"token", nil},
         {"amount", nil},
         {"fromSubAccount", nil},
         {"nonce", nil}
       ]},
    "sendToEvmWithData" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"token", nil},
         {"amount", nil},
         {"sourceDex", nil},
         {"destinationRecipient", nil},
         {"addressEncoding", nil},
         {"destinationChainId", nil},
         {"gasLimit", nil},
         {"data", nil},
         {"nonce", nil}
       ]},
    "setDisplayName" => {:object, [{"type", nil}, {"displayName", nil}]},
    "setReferrer" => {:object, [{"type", nil}, {"code", nil}]},
    "spotSend" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"destination", nil},
         {"token", nil},
         {"amount", nil},
         {"time", nil}
       ]},
    "spotUser" => {:object, [{"type", nil}, {"toggleSpotDusting", nil}]},
    "stakingLinkDisableTradingUser" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"tradingUser", nil},
         {"nonce", nil}
       ]},
    "subAccountModify" => {:object, [{"type", nil}, {"subAccountUser", nil}, {"name", nil}]},
    "subAccountSpotTransfer" =>
      {:object,
       [
         {"type", nil},
         {"subAccountUser", nil},
         {"isDeposit", nil},
         {"token", nil},
         {"amount", nil}
       ]},
    "subAccountTransfer" =>
      {:object, [{"type", nil}, {"subAccountUser", nil}, {"isDeposit", nil}, {"usd", nil}]},
    "tokenDelegate" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"validator", nil},
         {"wei", nil},
         {"isUndelegate", nil},
         {"nonce", nil}
       ]},
    "topUpIsolatedOnlyMargin" => {:object, [{"type", nil}, {"asset", nil}, {"leverage", nil}]},
    "twapCancel" => {:object, [{"type", nil}, {"a", nil}, {"t", nil}]},
    "twapOrder" => {:object, [{"type", nil}, {"twap", @twap_wire}, {"details", @twap_details}]},
    "updateIsolatedMargin" =>
      {:object, [{"type", nil}, {"asset", nil}, {"isBuy", nil}, {"ntli", nil}]},
    "updateLeverage" =>
      {:object, [{"type", nil}, {"asset", nil}, {"isCross", nil}, {"leverage", nil}]},
    "usdClassTransfer" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"amount", nil},
         {"toPerp", nil},
         {"nonce", nil}
       ]},
    "usdSend" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"destination", nil},
         {"amount", nil},
         {"time", nil}
       ]},
    "userDexAbstraction" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"user", nil},
         {"enabled", nil},
         {"nonce", nil}
       ]},
    "userPortfolioMargin" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"user", nil},
         {"enabled", nil},
         {"nonce", nil}
       ]},
    "userSetAbstraction" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"user", nil},
         {"abstraction", nil},
         {"nonce", nil}
       ]},
    "validatorL1Stream" => {:object, [{"type", nil}, {"riskFreeRate", nil}]},
    "vaultDistribute" => {:object, [{"type", nil}, {"vaultAddress", nil}, {"usd", nil}]},
    "vaultModify" =>
      {:object,
       [
         {"type", nil},
         {"vaultAddress", nil},
         {"allowDeposits", nil},
         {"alwaysCloseOnWithdraw", nil}
       ]},
    "vaultTransfer" =>
      {:object, [{"type", nil}, {"vaultAddress", nil}, {"isDeposit", nil}, {"usd", nil}]},
    "withdraw3" =>
      {:object,
       [
         {"type", nil},
         {"signatureChainId", nil},
         {"hyperliquidChain", nil},
         {"destination", nil},
         {"amount", nil},
         {"time", nil}
       ]}
  }

  @doc """
  Returns the canonical top-level key order for `action_type`, or `nil` when the
  action type has no declared order (deploy variants and validator actions,
  whose shape is a tagged union built by the caller).
  """
  @spec key_order(String.t()) :: [String.t()] | nil
  def key_order(action_type) do
    case Map.fetch(@specs, action_type) do
      {:ok, {:object, fields}} -> Enum.map(fields, &elem(&1, 0))
      :error -> nil
    end
  end

  @doc "All action types with a declared key order."
  @spec known_types() :: [String.t()]
  def known_types, do: Map.keys(@specs)

  @doc """
  Rewrite `action` into a `Jason.OrderedObject` whose keys follow the canonical
  Hyperliquid field order for its `type`.

  Actions whose `type` has no declared order are returned as an ordered object
  preserving the caller's own ordering (already explicit in those modules), so
  it is always safe to pipe an action through this function.
  """
  @spec ordered(term()) :: term()
  def ordered(action) do
    case action_type(action) do
      nil -> to_ordered_object(action)
      type -> walk(Map.get(@specs, type), action)
    end
  end

  defp action_type(action) do
    case fetch_any(action, "type") do
      {:ok, type} when is_binary(type) -> type
      {:ok, type} when is_atom(type) and not is_nil(type) -> Atom.to_string(type)
      _ -> nil
    end
  end

  # ===================== Walker =====================

  # Elixir tuples are not JSON-encodable; the deploy actions take `[{coin, v}]`
  # pair lists, which Hyperliquid expects as two-element arrays.
  defp walk(spec, tuple) when is_tuple(tuple),
    do: walk(spec, Tuple.to_list(tuple))

  defp walk({:array, spec}, list) when is_list(list), do: Enum.map(list, &walk(spec, &1))

  defp walk({:object, fields}, value) do
    if container?(value) do
      pairs = pairs(value)
      declared = Enum.map(fields, &elem(&1, 0))
      specs = Map.new(fields)

      ordered_pairs =
        Enum.flat_map(declared, fn key ->
          case take(pairs, key) do
            {:ok, orig_key, v} -> [{orig_key, walk(Map.get(specs, key), v)}]
            :error -> []
          end
        end)

      # Keys the schema does not declare (forward-compatibility seams) sort
      # lexicographically rather than keeping the caller's order: a plain Elixir
      # map has no insertion order, and its key order follows the atom table,
      # which is populated differently on every BEAM run.
      extras =
        pairs
        |> Enum.reject(fn {k, _v} -> to_string(k) in declared end)
        |> Enum.sort_by(fn {k, _v} -> to_string(k) end)

      Jason.OrderedObject.new(ordered_pairs ++ extras)
    else
      value
    end
  end

  defp walk(nil, value) when is_list(value), do: Enum.map(value, &walk(nil, &1))
  defp walk(nil, value), do: to_ordered_object(value)

  # Unknown-shape containers keep whatever order the caller gave them, but are
  # still converted to an ordered object so the encoded bytes are stable.
  defp to_ordered_object(%Jason.OrderedObject{} = obj), do: obj

  defp to_ordered_object(value) do
    if container?(value) do
      Jason.OrderedObject.new(Enum.sort_by(pairs(value), &sort_key/1))
    else
      value
    end
  end

  # `type` is the action discriminator and always leads; everything else in an
  # undeclared shape sorts lexicographically so the bytes are stable across runs.
  defp sort_key({k, _v}) do
    case to_string(k) do
      "type" -> {0, ""}
      other -> {1, other}
    end
  end

  defp container?(%Jason.OrderedObject{}), do: true
  defp container?(%_{}), do: false
  defp container?(value) when is_map(value), do: true
  defp container?(_), do: false

  defp pairs(%Jason.OrderedObject{values: values}), do: values
  defp pairs(map) when is_map(map), do: Enum.to_list(map)

  defp fetch_any(%Jason.OrderedObject{values: values}, key) do
    case Enum.find(values, fn {k, _v} -> to_string(k) == key end) do
      {_k, v} -> {:ok, v}
      nil -> :error
    end
  end

  defp fetch_any(map, key) when is_map(map) do
    case Enum.find(map, fn {k, _v} -> to_string(k) == key end) do
      {_k, v} -> {:ok, v}
      nil -> :error
    end
  end

  defp fetch_any(_other, _key), do: :error

  defp take(pairs, key) do
    case Enum.find(pairs, fn {k, _v} -> to_string(k) == key end) do
      {k, v} -> {:ok, k, v}
      nil -> :error
    end
  end

  # ===================== Signing =====================

  @doc """
  Canonicalize, encode and sign an L1 action.

  Returns `{:ok, ordered_action, action_json, signature}`. The caller sends
  `ordered_action` so the wire body and the signed bytes cannot drift apart.

  All L1 actions go through the generic ordered-msgpack path
  (`Signer.compute_connection_id_ex/4` + `Signer.sign_l1_action/3`): Elixir owns
  the key order, the NIF only hashes and signs. There is no per-action-type
  Rust struct in the signing path, so adding an action is a pure-Elixir change.
  """
  @spec sign(String.t(), term(), non_neg_integer(), String.t() | nil, non_neg_integer() | nil) ::
          {:ok, term(), String.t(), map()} | {:error, term()}
  def sign(private_key, action, nonce, vault_address, expires_after) do
    ordered = ordered(action)

    with {:ok, action_json} <- Jason.encode(ordered),
         {:ok, signature} <-
           sign_json(private_key, action_json, nonce, vault_address, expires_after) do
      {:ok, ordered, action_json, signature}
    end
  end

  @doc """
  Sign an already-encoded, already-ordered action JSON string.
  """
  @spec sign_json(
          String.t(),
          String.t(),
          non_neg_integer(),
          String.t() | nil,
          non_neg_integer() | nil
        ) ::
          {:ok, map()} | {:error, term()}
  def sign_json(private_key, action_json, nonce, vault_address, expires_after) do
    sign_json(private_key, action_json, nonce, vault_address, expires_after, Config.mainnet?())
  end

  @doc false
  def sign_json(private_key, action_json, nonce, vault_address, expires_after, is_mainnet) do
    case Signer.compute_connection_id_ex(action_json, nonce, vault_address, expires_after) do
      connection_id when is_binary(connection_id) ->
        case Signer.sign_l1_action(private_key, connection_id, is_mainnet) do
          %{"r" => r, "s" => s, "v" => v} -> {:ok, %{r: r, s: s, v: v}}
          error -> {:error, {:signing_error, error}}
        end

      error ->
        {:error, {:signing_error, error}}
    end
  end
end
