# Live TESTNET smoke test for the *user-signed* (EIP-712) action surface plus
# the perp L1 actions that need collateral. Companion to `testnet_smoke.exs`,
# which covers the agent-signable L1 surface.
#
# Usage:
#
#     eval "$(ssh eu-root cat /root/.hl-testnet/master.env)"   # HL_ACCOUNT, HL_MASTER_KEY
#     mix run --no-start scripts/testnet_smoke_master.exs
#
# Keys are read from the environment only — never hard-coded, logged or written.
#
#   HL_ACCOUNT      master address
#   HL_MASTER_KEY   master private key, hex
#   HL_AGENT_KEY    (optional) approved agent key, for the regression guard
#
# Classification: OK / RULE / SIGFAIL / SKIP — see testnet_smoke.exs.

Application.put_env(:hyperliquid, :chain, :testnet)
Application.put_env(:hyperliquid, :http_url, "https://api.hyperliquid-testnet.xyz")
Application.put_env(:hyperliquid, :ws_url, "wss://api.hyperliquid-testnet.xyz/ws")
Application.put_env(:hyperliquid, :enable_db, false)
Application.put_env(:hyperliquid, :enable_web, false)
Application.put_env(:hyperliquid, :autostart_cache, false)
Application.put_env(:hyperliquid, :debug, false)

account = System.fetch_env!("HL_ACCOUNT")
master_key = System.fetch_env!("HL_MASTER_KEY")
agent_key = System.get_env("HL_AGENT_KEY")
Application.put_env(:hyperliquid, :private_key, master_key)

{:ok, _} = Application.ensure_all_started(:hyperliquid)

alias Hyperliquid.Api.Exchange
alias Hyperliquid.Signer
alias Hyperliquid.Transport.Http

defmodule Smoke do
  @moduledoc false
  def start, do: Agent.start_link(fn -> [] end, name: __MODULE__)

  def record(name, class, message) do
    Agent.update(__MODULE__, &[{name, class, message} | &1])
    IO.puts(:stderr, "  [#{class}] #{name} — #{String.slice(to_string(message), 0, 200)}")
  end

  def results, do: Agent.get(__MODULE__, &Enum.reverse/1)

  def classify(result, signer_addr) do
    case result do
      {:ok, resp} ->
        {:ok, summarize(resp)}

      {:error, %Hyperliquid.Error{} = err} ->
        msg = err.message || inspect(err.reason)
        {class_of(msg, signer_addr), msg}

      {:error, other} ->
        {:sigfail, inspect(other)}
    end
  end

  defp class_of(msg, signer) do
    down = String.downcase(msg)
    signer = String.downcase(signer)

    cond do
      String.contains?(down, "failed to deserialize") -> :sigfail
      String.contains?(down, "unknown variant") -> :sigfail
      String.contains?(down, "missing field") -> :sigfail
      String.contains?(down, "invalid type") -> :sigfail
      String.contains?(down, "invalid length") -> :sigfail
      String.contains?(down, "must be") and String.contains?(down, "signature") -> :sigfail
      String.contains?(down, "does not exist") and stray_address?(down, signer) -> :sigfail
      true -> :rule
    end
  end

  defp stray_address?(msg, signer) do
    case Regex.run(~r/0x[0-9a-f]{40}/, msg) do
      [addr] -> addr != signer
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

  def filled?({:ok, %{"response" => %{"data" => %{"statuses" => statuses}}}}) do
    Enum.any?(statuses, &Map.has_key?(&1, "filled"))
  end

  def filled?(_), do: false
end

{:ok, _} = Smoke.start()

master_addr = Signer.derive_address(master_key)

unless String.downcase(master_addr) == String.downcase(account) do
  raise "HL_MASTER_KEY derives #{master_addr}, not HL_ACCOUNT"
end

step = fn name, fun ->
  result =
    try do
      fun.()
    rescue
      e -> {:error, {:exception, Exception.message(e)}}
    end

  {class, msg} = Smoke.classify(result, master_addr)
  Smoke.record(name, class, msg)
  Process.sleep(300)
  result
end

skip = fn name, reason -> Smoke.record(name, :skip, reason) end

# Phase selection so a partial re-run does not repeat one-way steps
# (e.g. approveAgent). HL_SMOKE_PHASES=A,B,C,D by default.
phases =
  (System.get_env("HL_SMOKE_PHASES") || "A,S,B,C,D")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)
  |> MapSet.new()

phase? = fn p -> MapSet.member?(phases, p) end

info = fn payload ->
  {:ok, r} = Http.info_request(payload, raw: true)
  r
end

# ===================== Constants / market data =====================

opts = [private_key: master_key]
sensitive = [private_key: master_key, expected_address: account]

builder_addr = "0xc2e85536528Ae9E9DA3FbE5A4aF4E03358C1CDd9"
hlp_vault = "0xa15099a30bbf2e68942d6f4c43d70d04faeab0a0"

spot_meta = info.(%{type: "spotMeta"})

tok = fn name ->
  t = Enum.find(spot_meta["tokens"], &(&1["name"] == name))
  {"#{t["name"]}:#{t["tokenId"]}", t["weiDecimals"]}
end

{usdc_token, _} = tok.("USDC")
{purr_token, _} = tok.("PURR")
{_hype_token, hype_wei_dec} = tok.("HYPE")

purr_asset = 10_000 + 0

perp_meta = info.(%{type: "meta"})
perp_idx = perp_meta["universe"] |> Enum.with_index() |> Map.new(fn {u, i} -> {u["name"], i} end)
perp_sz_dec = Map.new(perp_meta["universe"], &{&1["name"], &1["szDecimals"]})

perp_coin = "ETH"
eth_asset = Map.fetch!(perp_idx, perp_coin)
eth_sz_dec = Map.fetch!(perp_sz_dec, perp_coin)

num = fn
  nil ->
    0.0

  v when is_float(v) ->
    v

  v when is_integer(v) ->
    v * 1.0

  v when is_binary(v) ->
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
end

mids = info.(%{type: "allMids"})
eth_mid = num.(Map.fetch!(mids, perp_coin))

# Perp price: max 5 significant figures AND max (6 - szDecimals) decimals.
round_px = fn px, sz_dec ->
  max_dec = 6 - sz_dec
  sig = Float.round(px, max(0, 5 - (px |> :math.log10() |> Float.floor() |> trunc()) - 1))
  sig |> Float.round(max_dec) |> :erlang.float_to_binary([:short])
end

round_sz = fn sz, sz_dec -> sz |> Float.round(sz_dec) |> :erlang.float_to_binary([:short]) end

# ~$12 notional, comfortably above the $10 minimum.
eth_sz = round_sz.(12.0 / eth_mid, eth_sz_dec)
eth_buy_px = round_px.(eth_mid * 1.05, eth_sz_dec)
eth_sell_px = round_px.(eth_mid * 0.95, eth_sz_dec)
eth_far_px = round_px.(eth_mid * 0.5, eth_sz_dec)

IO.puts(:stderr, "\n=== account #{account} (master) ===")

IO.puts(
  :stderr,
  "ETH mid=#{eth_mid} sz=#{eth_sz} far=#{eth_far_px} buy=#{eth_buy_px} sell=#{eth_sell_px}\n"
)

# ===================== Snapshot =====================

snap = fn ->
  %{
    spot:
      info.(%{type: "spotClearinghouseState", user: account})["balances"]
      |> Enum.reject(&(&1["total"] == "0.0"))
      |> Map.new(&{&1["coin"], &1["total"]}),
    perp: info.(%{type: "clearinghouseState", user: account})["marginSummary"]["accountValue"],
    orders: info.(%{type: "openOrders", user: account}),
    staking: info.(%{type: "delegatorSummary", user: account}),
    agents: info.(%{type: "extraAgents", user: account})
  }
end

start_state = snap.()
start_oids = MapSet.new(start_state.orders, & &1["oid"])
IO.puts(:stderr, "starting open orders: #{length(start_state.orders)}")

subs =
  (info.(%{type: "subAccounts", user: account}) || [])
  |> Enum.filter(&(String.downcase(&1["master"]) == String.downcase(account)))

sub = List.first(subs)
sub_addr = sub && sub["subAccountUser"]

# ===================== A. User-signed, reversible =====================

throwaway_key = "0x" <> (:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower))
throwaway_addr = Signer.derive_address(throwaway_key)

if phase?.("A") do
  IO.puts(:stderr, "\n--- A. user-signed ---")

  # A1 — fund perp
  step.("A1 usdClassTransfer spot->perp 20 USDC", fn ->
    Exchange.UsdClassTransfer.request("20", true, opts)
  end)

  # A2 — builder fee
  step.("A2 approveBuilderFee 0.001%", fn ->
    Exchange.ApproveBuilderFee.request(builder_addr, "0.001%", sensitive)
  end)

  step.("A2 info:maxBuilderFee", fn ->
    {:ok, r} =
      Http.info_request(%{type: "maxBuilderFee", user: account, builder: builder_addr}, raw: true)

    {:ok, %{"response" => %{"data" => %{"maxBuilderFee" => r}}}}
  end)

  rb =
    step.("A2 order with builder field", fn ->
      Exchange.Order.place_batch(
        [Exchange.Order.limit(purr_asset, true, "2.21", "5")],
        :na,
        opts ++ [builder: %{builder: String.downcase(builder_addr), fee: 1}]
      )
    end)

  case Smoke.oid_of(rb) do
    nil ->
      skip.("A2 cancel builder order", "no resting oid")

    oid ->
      step.("A2 cancel builder order", fn -> Exchange.Cancel.cancel(purr_asset, oid, opts) end)
  end

  step.("A2 approveBuilderFee 0% (revert)", fn ->
    Exchange.ApproveBuilderFee.request(builder_addr, "0%", sensitive)
  end)

  # A3 — throwaway agent
  IO.puts(:stderr, "  throwaway agent address: #{throwaway_addr}")

  step.("A3 approveAgent elixir-smoke", fn ->
    Exchange.ApproveAgent.approve(throwaway_addr, sensitive ++ [agent_name: "elixir-smoke"])
  end)

  step.("A3 info:extraAgents contains it", fn ->
    agents = info.(%{type: "extraAgents", user: account}) || []

    found =
      Enum.find(agents, &(String.downcase(&1["address"]) == String.downcase(throwaway_addr)))

    if found, do: {:ok, found}, else: {:error, %Hyperliquid.Error{message: "agent not listed"}}
  end)

  ra =
    step.("A3 order signed by new agent", fn ->
      Exchange.Order.place(Exchange.Order.limit(purr_asset, true, "2.20", "5"),
        private_key: throwaway_key
      )
    end)

  case Smoke.oid_of(ra) do
    nil ->
      skip.("A3 cancel via new agent", "no resting oid")

    oid ->
      step.("A3 cancel via new agent", fn ->
        Exchange.Cancel.cancel(purr_asset, oid, private_key: throwaway_key)
      end)
  end

  # A4 — usdSend to sub-account
  if sub_addr do
    step.("A4 usdSend 1 USDC -> sub", fn ->
      Exchange.UsdSend.request(sub_addr, "1", sensitive)
    end)

    step.("A4 subAccountTransfer 1 USDC back", fn ->
      Exchange.SubAccountTransfer.request(sub_addr, false, 1_000_000, opts)
    end)

    # A5 — spotSend PURR
    step.("A5 spotSend 0.5 PURR -> sub", fn ->
      Exchange.SpotSend.request(sub_addr, purr_token, "0.5", sensitive)
    end)

    step.("A5 subAccountSpotTransfer 0.5 PURR back", fn ->
      Exchange.SubAccountSpotTransfer.request(sub_addr, false, purr_token, "0.5", opts)
    end)
  else
    skip.("A4/A5 sub-account transfers", "no sub-account found")
  end

  # A6 — sendAsset between own dexes
  step.("A6 sendAsset 1 USDC spot->perp", fn ->
    Exchange.SendAsset.request(account, "spot", "", usdc_token, "1", sensitive)
  end)

  step.("A6 sendAsset 1 USDC perp->spot", fn ->
    Exchange.SendAsset.request(account, "", "spot", usdc_token, "1", sensitive)
  end)
end

if phase?.("S") do
  # A7 — staking
  hype_wei = trunc(:math.pow(10, hype_wei_dec))

  validator =
    info.(%{type: "validatorSummaries"})
    |> Enum.reject(& &1["isJailed"])
    |> Enum.sort_by(&num.(&1["stake"]), :desc)
    |> List.first()
    |> Map.fetch!("validator")

  IO.puts(:stderr, "  validator: #{validator}")

  step.("A7 cDeposit 1 HYPE", fn -> Exchange.CDeposit.request(hype_wei, opts) end)

  step.("A7 tokenDelegate 1 HYPE", fn ->
    Exchange.TokenDelegate.request(validator, false, hype_wei, opts)
  end)

  step.("A7 tokenDelegate undelegate 1 HYPE", fn ->
    Exchange.TokenDelegate.request(validator, true, hype_wei, opts)
  end)

  step.("A7 cWithdraw 1 HYPE", fn -> Exchange.CWithdraw.request(hype_wei, opts) end)

  # A8 — abstraction toggles
  step.("A8 userDexAbstraction enable", fn ->
    Exchange.UserDexAbstraction.request(account, true, opts)
  end)

  step.("A8 userDexAbstraction disable", fn ->
    Exchange.UserDexAbstraction.request(account, false, opts)
  end)

  step.("A8 userPortfolioMargin on", fn ->
    Exchange.UserPortfolioMargin.request(account, true, opts)
  end)

  step.("A8 userPortfolioMargin off", fn ->
    Exchange.UserPortfolioMargin.request(account, false, opts)
  end)

  step.("A8 userSetAbstraction unifiedAccount (no-op)", fn ->
    Exchange.UserSetAbstraction.request(account, "unifiedAccount", opts)
  end)

  # A9 — core -> EVM
  step.("A9 sendToEvmWithData 1 USDC -> self", fn ->
    Exchange.SendToEvmWithData.request(
      usdc_token,
      "1",
      "spot",
      account,
      998,
      100_000,
      "0x",
      sensitive
    )
  end)

  # A10 — regression guard: agent key cannot user-sign
  if agent_key do
    step.("A10 usdClassTransfer with AGENT key (expect refusal)", fn ->
      Exchange.UsdClassTransfer.request("0.000001", true, private_key: agent_key)
    end)
  else
    skip.("A10 usdClassTransfer with AGENT key", "HL_AGENT_KEY not set")
  end

  # claimRewards (harmless — claims accrued referral rewards)
  step.("A11 claimRewards", fn -> Exchange.ClaimRewards.request(opts) end)
end

# ===================== B. Deliberately skipped =====================

skip.("B withdraw3", "BLOCKED — bridge withdrawal, costs a fee and leaves testnet")
skip.("B convertToMultiSigUser", "BLOCKED — irreversible account conversion")
skip.("B linkStakingUser", "BLOCKED — creates a persistent staking link")
skip.("B stakingLinkDisableTradingUser", "BLOCKED — persistent, disables trading")
skip.("B multiSig", "BLOCKED — requires a converted multi-sig user")
skip.("B agentSendAsset", "BLOCKED — moves funds via agent, no reversible target")
skip.("B createVault / vaultModify / vaultDistribute", "BLOCKED — creates persistent vault state")

# ===================== C. Perp actions =====================

if phase?.("C") do
  IO.puts(:stderr, "\n--- C. perp ---")

  step.("C1 updateLeverage ETH cross 5x", fn ->
    Exchange.UpdateLeverage.request(eth_asset, 5, true, opts)
  end)

  rp =
    step.("C2 perp limit far from mark", fn ->
      # Resting orders are valued at their own limit price, so a half-mark order
      # needs double the size to clear the $10 minimum.
      Exchange.Order.place(
        Exchange.Order.limit(
          eth_asset,
          true,
          eth_far_px,
          round_sz.(12.0 / (eth_mid * 0.5), eth_sz_dec)
        ),
        opts
      )
    end)

  case Smoke.oid_of(rp) do
    nil -> skip.("C2 cancel perp limit", "no resting oid")
    oid -> step.("C2 cancel perp limit", fn -> Exchange.Cancel.cancel(eth_asset, oid, opts) end)
  end

  rprio =
    step.("C3 order priority grouping {p:_}", fn ->
      Exchange.Order.place_batch(
        [
          Exchange.Order.limit(
            eth_asset,
            true,
            eth_far_px,
            round_sz.(12.0 / (eth_mid * 0.5), eth_sz_dec),
            tif: "Alo"
          )
        ],
        {:priority, 1000},
        opts
      )
    end)

  case Smoke.oid_of(rprio) do
    nil ->
      skip.("C3 cancel priority order", "no resting oid")

    oid ->
      step.("C3 cancel priority order", fn -> Exchange.Cancel.cancel(eth_asset, oid, opts) end)
  end

  ropen =
    step.("C4 IOC perp open ~$12 ETH", fn ->
      Exchange.Order.place(
        Exchange.Order.limit(eth_asset, true, eth_buy_px, eth_sz, tif: "Ioc"),
        opts
      )
    end)

  if Smoke.filled?(ropen) do
    step.("C4 IOC perp close", fn ->
      Exchange.Order.place(
        Exchange.Order.limit(eth_asset, false, eth_sell_px, eth_sz,
          tif: "Ioc",
          reduce_only: true
        ),
        opts
      )
    end)
  else
    skip.("C4 IOC perp close", "open did not fill")
  end

  step.("C5 updateLeverage ETH isolated 5x", fn ->
    Exchange.UpdateLeverage.request(eth_asset, 5, false, opts)
  end)

  riso =
    step.("C6 IOC open isolated ~$12 ETH", fn ->
      Exchange.Order.place(
        Exchange.Order.limit(eth_asset, true, eth_buy_px, eth_sz, tif: "Ioc"),
        opts
      )
    end)

  step.("C6 updateIsolatedMargin +1 USDC", fn ->
    Exchange.UpdateIsolatedMargin.request(eth_asset, true, 1_000_000, opts)
  end)

  step.("C6 updateIsolatedMargin -1 USDC", fn ->
    Exchange.UpdateIsolatedMargin.request(eth_asset, true, -1_000_000, opts)
  end)

  step.("C6 topUpIsolatedOnlyMargin", fn ->
    Exchange.TopUpIsolatedOnlyMargin.request(eth_asset, "3", opts)
  end)

  if Smoke.filled?(riso) do
    step.("C6 close isolated position", fn ->
      Exchange.Order.place(
        Exchange.Order.limit(eth_asset, false, eth_sell_px, eth_sz,
          tif: "Ioc",
          reduce_only: true
        ),
        opts
      )
    end)
  else
    skip.("C6 close isolated position", "open did not fill")
  end

  step.("C7 vaultTransfer deposit 5 USDC HLP", fn ->
    Exchange.VaultTransfer.request(hlp_vault, true, 5_000_000, opts)
  end)

  step.("C7 vaultTransfer withdraw 5 USDC HLP", fn ->
    Exchange.VaultTransfer.request(hlp_vault, false, 5_000_000, opts)
  end)

  step.("C8 scheduleCancel", fn ->
    Exchange.ScheduleCancel.request(System.system_time(:millisecond) + 60_000, opts)
  end)

  step.("C9 reserveRequestWeight (master)", fn ->
    Exchange.ReserveRequestWeight.request(1, opts)
  end)
end

# ===================== D. Cleanup =====================

IO.puts(:stderr, "\n--- D. cleanup ---")

asset_of =
  Map.merge(
    perp_idx,
    Map.new(spot_meta["universe"], &{&1["name"], 10_000 + &1["index"]})
  )

leftover =
  info.(%{type: "openOrders", user: account})
  |> Enum.reject(&MapSet.member?(start_oids, &1["oid"]))

if leftover != [] do
  cancels = for o <- leftover, a = Map.get(asset_of, o["coin"]), do: %{asset: a, oid: o["oid"]}

  step.("D cancel #{length(cancels)} leftover order(s)", fn ->
    Exchange.Cancel.cancel_batch(cancels, opts)
  end)
end

# Close any perp position we still hold.
positions = info.(%{type: "clearinghouseState", user: account})["assetPositions"] || []

for %{"position" => p} <- positions do
  coin = p["coin"]
  szi = num.(p["szi"])
  a = Map.get(asset_of, coin)

  if a && szi != 0.0 do
    mid = num.(Map.get(mids, coin, "0"))
    px = round_px.(if(szi > 0, do: mid * 0.9, else: mid * 1.1), Map.get(perp_sz_dec, coin, 2))

    step.("D close leftover #{coin} position", fn ->
      Exchange.Order.place(
        Exchange.Order.limit(a, szi < 0, px, abs(szi) |> Float.to_string(),
          tif: "Ioc",
          reduce_only: true
        ),
        opts
      )
    end)
  end
end

Process.sleep(1500)

perp_value = num.(info.(%{type: "clearinghouseState", user: account})["withdrawable"])

if perp_value > 0.0 do
  amt = perp_value |> Float.floor(2) |> :erlang.float_to_binary(decimals: 2)

  step.("D usdClassTransfer perp->spot #{amt} USDC", fn ->
    Exchange.UsdClassTransfer.request(amt, false, opts)
  end)
end

Process.sleep(2000)
end_state = snap.()

# ===================== Report =====================

IO.puts("\n==================== RESULT MATRIX ====================")

for {name, class, msg} <- Smoke.results() do
  label =
    case class do
      :ok -> "OK"
      :rule -> "RULE"
      :sigfail -> "SIGFAIL"
      :skip -> "SKIPPED"
    end

  IO.puts(
    "#{String.pad_trailing(name, 46)} | #{String.pad_trailing(label, 8)} | #{String.slice(to_string(msg), 0, 220)}"
  )
end

IO.puts("\n==================== STATE ====================")
IO.puts("spot start: #{inspect(start_state.spot)}")
IO.puts("spot end:   #{inspect(end_state.spot)}")
IO.puts("perp start: #{start_state.perp}   perp end: #{end_state.perp}")
IO.puts("staking start: #{inspect(start_state.staking)}")
IO.puts("staking end:   #{inspect(end_state.staking)}")
IO.puts("open orders: start=#{length(start_state.orders)} end=#{length(end_state.orders)}")
IO.puts("agents start: #{inspect(Enum.map(start_state.agents, & &1["name"]))}")
IO.puts("agents end:   #{inspect(Enum.map(end_state.agents, & &1["name"]))}")

if phase?.("A") do
  IO.puts("throwaway agent left approved: #{throwaway_addr} (name elixir-smoke)")
end

IO.puts("\ncounts: #{inspect(Smoke.results() |> Enum.frequencies_by(fn {_, c, _} -> c end))}")
