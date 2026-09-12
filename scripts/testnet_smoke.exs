# Live TESTNET smoke test for the signed /exchange action surface.
#
# Usage:
#
#     set -a; . /path/to/hl-testnet.env; set +a   # exports HL_ACCOUNT, HL_AGENT_KEY
#     mix run --no-start scripts/testnet_smoke.exs
#
# The key is read from the environment only — never hard-code or log it.
#
#   HL_ACCOUNT            master address the agent is approved for
#   HL_AGENT_KEY          approved agent (API-wallet) private key, hex
#   HL_SMOKE_SKIP_FILLS=1 skip the IOC round-trip that actually trades
#
# Every step is classified as one of:
#   OK      exchange accepted and executed the action
#   RULE    signature accepted, business rule rejected (message recorded)
#   SIGFAIL signature/encoding rejected -> SDK bug
#   SKIP    not attempted (blocked)

Application.put_env(:hyperliquid, :chain, :testnet)
Application.put_env(:hyperliquid, :http_url, "https://api.hyperliquid-testnet.xyz")
Application.put_env(:hyperliquid, :ws_url, "wss://api.hyperliquid-testnet.xyz/ws")
Application.put_env(:hyperliquid, :enable_db, false)
Application.put_env(:hyperliquid, :enable_web, false)
Application.put_env(:hyperliquid, :autostart_cache, false)
Application.put_env(:hyperliquid, :debug, false)

account = System.fetch_env!("HL_ACCOUNT")
agent_key = System.fetch_env!("HL_AGENT_KEY")
Application.put_env(:hyperliquid, :private_key, agent_key)

{:ok, _} = Application.ensure_all_started(:hyperliquid)

alias Hyperliquid.Api.Exchange
alias Hyperliquid.Signer
alias Hyperliquid.Transport.Http

defmodule Smoke do
  @moduledoc false

  def start, do: Agent.start_link(fn -> [] end, name: __MODULE__)

  def record(name, class, message) do
    Agent.update(__MODULE__, &[{name, class, message} | &1])
    IO.puts(:stderr, "  [#{class}] #{name} — #{String.slice(to_string(message), 0, 180)}")
  end

  def results, do: Agent.get(__MODULE__, &Enum.reverse/1)

  @doc """
  Classify an SDK result.

  A signature/encoding failure is the case where the exchange could not
  attribute the action to our signer: it failed to deserialize the action, or
  it recovered an address that is not our agent. A "does not exist" naming our
  *own* agent address means the bytes were fine and the exchange simply
  refuses that signer for that action.
  """
  def classify(result, agent_addr) do
    case result do
      {:ok, resp} ->
        {:ok, summarize(resp)}

      {:error, %Hyperliquid.Error{} = err} ->
        msg = err.message || inspect(err.reason)
        {class_of(msg, agent_addr), msg}

      {:error, other} ->
        {:sigfail, inspect(other)}
    end
  end

  defp class_of(msg, agent_addr) do
    down = String.downcase(msg)
    agent = String.downcase(agent_addr)

    cond do
      String.contains?(down, "failed to deserialize") -> :sigfail
      String.contains?(down, "unknown variant") -> :sigfail
      String.contains?(down, "missing field") -> :sigfail
      String.contains?(down, "invalid type") -> :sigfail
      String.contains?(down, "invalid length") -> :sigfail
      String.contains?(down, "must be") and String.contains?(down, "signature") -> :sigfail
      String.contains?(down, "does not exist") and stray_address?(down, agent) -> :sigfail
      true -> :rule
    end
  end

  defp stray_address?(msg, agent) do
    case Regex.run(~r/0x[0-9a-f]{40}/, msg) do
      [addr] -> addr != agent
      _ -> false
    end
  end

  def summarize(%{"response" => %{"data" => %{"statuses" => s}}}), do: inspect(s)
  def summarize(%{"response" => %{"data" => d}}), do: inspect(d)
  def summarize(%{"response" => r}), do: inspect(r)
  def summarize(other), do: other |> inspect() |> String.slice(0, 220)

  def oid_of({:ok, %{"response" => %{"data" => %{"statuses" => statuses}}}}) do
    Enum.find_value(statuses, fn
      %{"resting" => %{"oid" => oid}} -> oid
      _ -> nil
    end)
  end

  def oid_of(_), do: nil

  # Exchange responses come back snake_cased by the transport, so twapId is twap_id.
  def twap_id_of({:ok, resp}) do
    get_in(resp, ["response", "data", "status", "running", "twap_id"]) ||
      get_in(resp, ["response", "data", "status", "running", "twapId"])
  end

  def twap_id_of(_), do: nil
end

{:ok, _} = Smoke.start()

agent_addr = Signer.derive_address(agent_key)

# Runs a step, records its classification, returns the raw SDK result.
step = fn name, fun ->
  result =
    try do
      fun.()
    rescue
      e -> {:error, {:exception, Exception.message(e)}}
    end

  {class, msg} = Smoke.classify(result, agent_addr)
  Smoke.record(name, class, msg)
  Process.sleep(250)
  result
end

skip = fn name, reason -> Smoke.record(name, :skip, reason) end

info = fn payload ->
  {:ok, r} = Http.info_request(payload, raw: true)
  r
end

# ===================== Constants =====================

# Spot asset ids are 10_000 + spot pair index.
purr = 10_000 + 0
# Testnet perp universe order differs from mainnet: index 3 is BTC (0 is SOL).
btc_perp = 3
opts = [private_key: agent_key]

# coin -> asset id, so cleanup can cancel whatever it finds resting.
perp_assets =
  info.(%{type: "meta"})
  |> Map.fetch!("universe")
  |> Enum.with_index()
  |> Map.new(fn {u, i} -> {u["name"], i} end)

spot_assets =
  info.(%{type: "spotMeta"})
  |> Map.fetch!("universe")
  |> Map.new(&{&1["name"], 10_000 + &1["index"]})

asset_of = Map.merge(perp_assets, spot_assets)

usdc_token =
  info.(%{type: "spotMeta"})
  |> Map.fetch!("tokens")
  |> Enum.find(&(&1["name"] == "USDC"))
  |> then(&"#{&1["name"]}:#{&1["tokenId"]}")

IO.puts(:stderr, "\n=== account #{account} / agent #{agent_addr} ===\n")

start_spot = info.(%{type: "spotClearinghouseState", user: account})
start_orders = info.(%{type: "openOrders", user: account})
start_oids = MapSet.new(start_orders, & &1["oid"])
IO.puts(:stderr, "starting open orders: #{length(start_orders)}")

# ===================== 1. Info sanity =====================

step.("info:extraAgents", fn -> Hyperliquid.Api.Info.ExtraAgents.request(account) end)

step.("info:spotClearinghouseState", fn ->
  Hyperliquid.Api.Info.SpotClearinghouseState.request(account)
end)

step.("info:clearinghouseState", fn ->
  Hyperliquid.Api.Info.ClearinghouseState.request(account)
end)

step.("info:openOrders", fn -> Hyperliquid.Api.Info.OpenOrders.request(account) end)

# ===================== 2. Spot L1 actions =====================

r1 =
  step.("order:spot limit buy (rests)", fn ->
    Exchange.Order.place(Exchange.Order.limit(purr, true, "2.3", "5"), opts)
  end)

case Smoke.oid_of(r1) do
  nil -> skip.("cancel:by oid", "no resting oid returned")
  oid -> step.("cancel:by oid", fn -> Exchange.Cancel.cancel(purr, oid, opts) end)
end

rf =
  step.("order:for fast cancel", fn ->
    Exchange.Order.place(Exchange.Order.limit(purr, true, "2.31", "5"), opts)
  end)

case Smoke.oid_of(rf) do
  nil ->
    skip.("cancel:with fast flag f=true", "no resting oid returned")

  oid ->
    step.("cancel:with fast flag f=true", fn ->
      Exchange.Cancel.cancel_batch([%{asset: purr, oid: oid}], opts ++ [fast: true])
    end)
end

# --- cloid order + cancelByCloid
cloid = "0x" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))

rc =
  step.("order:with cloid", fn ->
    Exchange.Order.place(Exchange.Order.limit(purr, true, "2.28", "5", cloid: cloid), opts)
  end)

case rc do
  {:ok, _} -> step.("cancelByCloid", fn -> Exchange.CancelByCloid.cancel(purr, cloid, opts) end)
  _ -> skip.("cancelByCloid", "order with cloid was not accepted")
end

cloid2 = "0x" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))

rc2 =
  step.("order:with cloid (for fast cancel)", fn ->
    Exchange.Order.place(Exchange.Order.limit(purr, true, "2.32", "5", cloid: cloid2), opts)
  end)

case rc2 do
  {:ok, _} ->
    step.("cancelByCloid:with fast flag f=true", fn ->
      Exchange.CancelByCloid.cancel_batch([%{asset: purr, cloid: cloid2}], opts ++ [fast: true])
    end)

  _ ->
    skip.("cancelByCloid:with fast flag f=true", "order was not accepted")
end

# --- modify / batchModify
rm =
  step.("order:for modify", fn ->
    Exchange.Order.place(Exchange.Order.limit(purr, true, "2.27", "5"), opts)
  end)

mod_oid = Smoke.oid_of(rm)

rmod =
  if mod_oid do
    step.("modify (single)", fn ->
      Exchange.Modify.modify(mod_oid, Exchange.Order.limit(purr, true, "2.26", "5"), opts)
    end)
  else
    skip.("modify (single)", "no resting order")
    nil
  end

mod_oid2 = Smoke.oid_of(rmod) || mod_oid

rbm =
  if mod_oid2 do
    step.("batchModify", fn ->
      Exchange.BatchModify.modify_batch(
        [%{oid: mod_oid2, order: Exchange.Order.limit(purr, true, "2.25", "5")}],
        opts
      )
    end)
  else
    skip.("batchModify", "no resting order")
    nil
  end

_ = rbm

step.("order:batch (2 orders)", fn ->
  Exchange.Order.place_batch(
    [
      Exchange.Order.limit(purr, true, "2.24", "5"),
      Exchange.Order.limit(purr, true, "2.23", "5")
    ],
    :na,
    opts
  )
end)

# Priority grouping {p: n}: every order must be a non-reduce-only ALO (or all IOC).
step.("order:priority grouping {p:_}", fn ->
  Exchange.Order.place_batch(
    [Exchange.Order.limit(purr, true, "2.22", "5", tif: "Alo")],
    {:priority, 1000},
    opts
  )
end)

# Trigger order exercising the `:extra` passthrough while leaving it unused.
step.("order:trigger, :extra unused", fn ->
  Exchange.Order.place(
    Exchange.Order.trigger(purr, true, "5.5", "5", "5.4", tpsl: "sl", is_market: false),
    opts
  )
end)

step.("order:with builder field", fn ->
  Exchange.Order.place_batch(
    [Exchange.Order.limit(purr, true, "2.21", "5")],
    :na,
    opts ++ [builder: %{builder: "0x0000000000000000000000000000000000000001", fee: 1}]
  )
end)

if System.get_env("HL_SMOKE_SKIP_FILLS") == "1" do
  skip.("order:IOC spot buy 3 PURR (fills)", "HL_SMOKE_SKIP_FILLS=1")
  skip.("order:IOC spot sell 3 PURR (reverse)", "HL_SMOKE_SKIP_FILLS=1")
else
  step.("order:IOC spot buy 3 PURR (fills)", fn ->
    Exchange.Order.place(Exchange.Order.limit(purr, true, "4.85", "3", tif: "Ioc"), opts)
  end)

  step.("order:IOC spot sell 3 PURR (reverse)", fn ->
    Exchange.Order.place(Exchange.Order.limit(purr, false, "4.35", "3", tif: "Ioc"), opts)
  end)
end

step.("scheduleCancel", fn ->
  Exchange.ScheduleCancel.request(System.system_time(:millisecond) + 60_000, opts)
end)

step.("scheduleCancel (clear)", fn -> Exchange.ScheduleCancel.request(nil, opts) end)

twap =
  step.("twapOrder (spot, 5m)", fn ->
    Exchange.TwapOrder.request(purr, true, "25", Keyword.merge(opts, duration_minutes: 5))
  end)

case Smoke.twap_id_of(twap) do
  nil -> skip.("twapCancel", "no running TWAP id returned")
  id -> step.("twapCancel", fn -> Exchange.TwapCancel.request(purr, id, opts) end)
end

step.("reserveRequestWeight", fn -> Exchange.ReserveRequestWeight.request(1, opts) end)
step.("noop", fn -> Exchange.Noop.request(opts) end)

step.("spotUser optOutOfSpotDusting(true)", fn ->
  Exchange.SpotUser.toggle_spot_dusting(true, opts)
end)

step.("spotUser optOutOfSpotDusting(false)", fn ->
  Exchange.SpotUser.toggle_spot_dusting(false, opts)
end)

step.("evmUserModify usingBigBlocks(true)", fn -> Exchange.EvmUserModify.request(true, opts) end)

step.("evmUserModify usingBigBlocks(false)", fn -> Exchange.EvmUserModify.request(false, opts) end)

step.("setDisplayName", fn -> Exchange.SetDisplayName.request("hl-elixir-smoke", opts) end)
step.("setDisplayName (clear)", fn -> Exchange.SetDisplayName.request("", opts) end)

step.("registerReferrer", fn -> Exchange.RegisterReferrer.request("ELIXIRSMOKE", opts) end)
step.("setReferrer (bogus code)", fn -> Exchange.SetReferrer.request("ZZZZNOPE", opts) end)

# --- sub-accounts
subs =
  (info.(%{type: "subAccounts", user: account}) || [])
  |> Enum.filter(&(String.downcase(&1["master"]) == String.downcase(account)))

case subs do
  [] ->
    step.("createSubAccount", fn -> Exchange.CreateSubAccount.request("elixir-smoke", opts) end)

  [s | _] ->
    skip.("createSubAccount", "#{length(subs)} sub-account(s) already exist — not creating more")

    step.("subAccountModify (rename to same name)", fn ->
      Exchange.SubAccountModify.request(s["name"],
        private_key: agent_key,
        sub_account_user: s["subAccountUser"]
      )
    end)

    step.("subAccountTransfer (0 usd)", fn ->
      Exchange.SubAccountTransfer.request(s["subAccountUser"], true, 0, opts)
    end)

    step.("subAccountSpotTransfer (0.000001 USDC)", fn ->
      Exchange.SubAccountSpotTransfer.request(
        s["subAccountUser"],
        true,
        usdc_token,
        "0.000001",
        opts
      )
    end)
end

# --- perp actions (account has no perp collateral)
step.("updateLeverage (BTC cross 5x)", fn ->
  Exchange.UpdateLeverage.request(btc_perp, 5, true, opts)
end)

step.("updateIsolatedMargin (no position)", fn ->
  Exchange.UpdateIsolatedMargin.request(btc_perp, true, 1, opts)
end)

step.("order:perp limit (no margin)", fn ->
  Exchange.Order.place(Exchange.Order.limit(btc_perp, true, "10000", "0.01"), opts)
end)

step.("topUpIsolatedOnlyMargin", fn ->
  Exchange.TopUpIsolatedOnlyMargin.request(btc_perp, "3", opts)
end)

# ===================== 3. Newer / exotic L1 actions =====================

step.("userOutcome splitOutcome (nonexistent)", fn ->
  Exchange.UserOutcome.split_outcome(999_999, "1", opts)
end)

step.("activateOutcomeDeployer (nonexistent venue)", fn ->
  Exchange.ActivateOutcomeDeployer.activate("zzzz", opts)
end)

step.("outcomeDeploy setSubDeployers (nonexistent venue)", fn ->
  Exchange.OutcomeDeploy.set_sub_deployers(
    "zzzz",
    [%{variant: "settleOutcome", user: account, allowed: false}],
    opts
  )
end)

step.("perpDeploy disableDex (nonexistent dex)", fn ->
  Exchange.PerpDeploy.disable_dex("zzzzz", opts)
end)

step.("spotDeploy disableQuoteToken (nonexistent token)", fn ->
  Exchange.SpotDeploy.disable_quote_token(999_999, opts)
end)

step.("finalizeEvmContract (nonexistent token)", fn ->
  Exchange.FinalizeEvmContract.request(999_999, :first_storage_slot, opts)
end)

step.("authorizeAqav2Role (nonexistent token)", fn ->
  Exchange.AuthorizeAqav2Role.request(999_999, "technical", opts)
end)

step.("gossipPriorityBid", fn -> Exchange.GossipPriorityBid.request(0, "1.2.3.4", 1, opts) end)

step.("hip3LiquidatorTransfer (nonexistent dex)", fn ->
  Exchange.Hip3LiquidatorTransfer.request("zzzzz", 1, true, opts)
end)

skip.("agentSendAsset", "BLOCKED — would move real funds")

skip.(
  "vaultTransfer / createVault / vaultModify / vaultDistribute",
  "BLOCKED — costs USDC / creates persistent state"
)

skip.("claimRewards", "BLOCKED — would claim unclaimed referral rewards")
skip.("borrowLend", "BLOCKED — would open a real borrow/lend position")

# ===================== 4. User-signed (EIP-712) with an agent key =====================

step.("usdClassTransfer (agent key, expect refusal)", fn ->
  Exchange.UsdClassTransfer.request("0.000001", true, opts)
end)

for a <- ~w(usdSend spotSend withdraw3 approveAgent approveBuilderFee tokenDelegate
            cDeposit cWithdraw sendAsset convertToMultiSigUser userDexAbstraction
            userPortfolioMargin linkStakingUser userSetAbstraction sendToEvmWithData
            stakingLinkDisableTradingUser) do
  skip.(
    "user-signed:#{a}",
    "BLOCKED — agent keys cannot sign user-signed actions (needs master key)"
  )
end

skip.("multiSig", "BLOCKED — requires a converted multi-sig user")

# ===================== 5. Cleanup =====================

IO.puts(:stderr, "\n=== cleanup ===")

to_cancel =
  info.(%{type: "openOrders", user: account})
  |> Enum.reject(&MapSet.member?(start_oids, &1["oid"]))

if to_cancel != [] do
  cancels =
    for o <- to_cancel, asset = Map.get(asset_of, o["coin"]), do: %{asset: asset, oid: o["oid"]}

  step.("cleanup:cancel #{length(cancels)} order(s)", fn ->
    Exchange.Cancel.cancel_batch(cancels, opts)
  end)
end

Process.sleep(2000)
end_spot = info.(%{type: "spotClearinghouseState", user: account})
end_orders = info.(%{type: "openOrders", user: account})

bal = fn state ->
  state["balances"]
  |> Enum.reject(&(&1["total"] == "0.0"))
  |> Map.new(&{&1["coin"], &1["total"]})
end

IO.puts("\n==================== RESULT MATRIX ====================")

for {name, class, msg} <- Smoke.results() do
  label =
    case class do
      :ok -> "SIGNATURE_ACCEPTED_AND_SUCCEEDED"
      :rule -> "SIGNATURE_ACCEPTED_BUT_RULE_REJECTED"
      :sigfail -> "SIGNATURE_OR_ENCODING_FAILURE"
      :skip -> "BLOCKED/SKIPPED"
    end

  IO.puts(
    "#{String.pad_trailing(name, 46)} | #{String.pad_trailing(label, 36)} | #{String.slice(to_string(msg), 0, 240)}"
  )
end

IO.puts("\n==================== BALANCES ====================")
IO.puts("start: #{inspect(bal.(start_spot))}")
IO.puts("end:   #{inspect(bal.(end_spot))}")
IO.puts("open orders: start=#{length(start_orders)} end=#{length(end_orders)}")

IO.puts("\ncounts: #{inspect(Smoke.results() |> Enum.frequencies_by(fn {_, c, _} -> c end))}")
