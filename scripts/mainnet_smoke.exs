# Live MAINNET smoke test for the signed /exchange action surface.
#
# Harness (Smoke module, `step`/`skip`/classification) copied from
# scripts/testnet_smoke.exs — that file is owned by another run and is not
# modified here.
#
# Usage:
#
#     eval "$(ssh -o BatchMode=yes eu-root cat /root/.hl-testnet/master.env)"
#     mix run --no-start scripts/mainnet_smoke.exs
#
# HARD SAFETY RULES enforced below:
#   * every order is a resting limit >= 15% away from mid on the passive side
#   * $10 <= notional <= $12, cancelled in the same run
#   * no IOC / market / trigger orders
#   * no withdraw3, no sendToEvmWithData, no vault/staking/referral/deploy
#   * transfers only to the operator's own account or its own sub-account, <= 5 USDC
#   * aborts if total USDC across master + subs drifts from the starting total

Application.put_env(:hyperliquid, :chain, :mainnet)
Application.put_env(:hyperliquid, :is_mainnet, true)
Application.put_env(:hyperliquid, :http_url, "https://api.hyperliquid.xyz")
Application.put_env(:hyperliquid, :ws_url, "wss://api.hyperliquid.xyz/ws")
Application.put_env(:hyperliquid, :signature_chain_id, 42_161)
Application.put_env(:hyperliquid, :enable_db, false)
Application.put_env(:hyperliquid, :enable_web, false)
Application.put_env(:hyperliquid, :autostart_cache, false)
Application.put_env(:hyperliquid, :debug, false)

account = System.fetch_env!("HL_ACCOUNT")
master_key = System.fetch_env!("HL_MASTER_KEY")
Application.put_env(:hyperliquid, :private_key, master_key)

{:ok, _} = Application.ensure_all_started(:hyperliquid)

alias Hyperliquid.Api.Exchange
alias Hyperliquid.Api.Info
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
        msg = summarize(resp)
        if inner_error?(resp), do: {:rule, msg}, else: {:ok, msg}

      {:error, %Hyperliquid.Error{} = err} ->
        msg = err.message || inspect(err.reason)
        {class_of(msg, signer_addr), msg}

      {:error, other} ->
        {:sigfail, inspect(other)}
    end
  end

  # A 200 OK whose per-order statuses contain {"error" => ...} means the
  # signature was fine and a business rule rejected the order.
  defp inner_error?(%{"response" => %{"data" => %{"statuses" => statuses}}})
       when is_list(statuses) do
    Enum.any?(statuses, &match?(%{"error" => _}, &1))
  end

  defp inner_error?(_), do: false

  defp class_of(msg, signer_addr) do
    down = String.downcase(msg)
    signer = String.downcase(signer_addr)

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
  def summarize(other), do: other |> inspect() |> String.slice(0, 260)

  def oid_of({:ok, %{"response" => %{"data" => %{"statuses" => statuses}}}}) do
    Enum.find_value(statuses, fn
      %{"resting" => %{"oid" => oid}} -> oid
      _ -> nil
    end)
  end

  def oid_of(_), do: nil

  def oids_of({:ok, %{"response" => %{"data" => %{"statuses" => statuses}}}}) do
    for %{"resting" => %{"oid" => oid}} <- statuses, do: oid
  end

  def oids_of(_), do: []
end

{:ok, _} = Smoke.start()

master_addr = Signer.derive_address(master_key)

unless String.downcase(master_addr) == String.downcase(account) do
  raise "derive_address mismatch: #{master_addr} != #{account}"
end

unless Hyperliquid.Config.mainnet?() and
         Hyperliquid.Config.api_base() == "https://api.hyperliquid.xyz" and
         Hyperliquid.Config.signature_chain_id() == 42_161 do
  raise "mainnet config not applied"
end

IO.puts(:stderr, "\n=== MAINNET  master #{master_addr}  sigChainId 0xa4b1 ===\n")

info = fn payload ->
  {:ok, r} = Http.info_request(payload, raw: true)
  r
end

step = fn name, signer, fun ->
  result =
    try do
      fun.()
    rescue
      e -> {:error, {:exception, Exception.message(e)}}
    end

  {class, msg} = Smoke.classify(result, signer)
  Smoke.record(name, class, msg)
  Process.sleep(400)
  result
end

skip = fn name, reason -> Smoke.record(name, :skip, reason) end

mopts = [private_key: master_key]

# ===================== Price / size helpers =====================

sig5 = fn px ->
  exp = :math.log10(abs(px)) |> :math.floor() |> trunc()
  f = :math.pow(10, 4 - exp)
  Float.round(px * f) / f
end

# Passive far price: buy 20% below mid (>= 15% away), rounded to 5 sig figs and
# to the venue's max decimal places.
far_px = fn mid, sz_decimals, spot? ->
  max_dec = if(spot?, do: 8, else: 6) - sz_decimals
  px = sig5.(mid * 0.80)
  Float.round(px, max(max_dec, 0))
end

# Largest size at `px` whose notional stays in [10, 12].
size_for = fn px, sz_decimals ->
  raw = 11.0 / px
  f = :math.pow(10, sz_decimals)
  sz = Float.floor(raw * f) / f
  ntl = sz * px

  cond do
    ntl >= 10.0 and ntl <= 12.0 -> {:ok, :erlang.float_to_binary(sz, decimals: sz_decimals), ntl}
    true -> {:error, "cannot fit $10-$12 notional at px=#{px} szDecimals=#{sz_decimals}"}
  end
end

fmt = fn f, dec -> :erlang.float_to_binary(f * 1.0, decimals: dec) end

to_f = fn
  v when is_number(v) ->
    v * 1.0

  v when is_binary(v) ->
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end

  _ ->
    0.0
end

# ===================== Universe =====================

spot_meta = info.(%{type: "spotMeta"})
perp_meta = info.(%{type: "meta"})
mids = info.(%{type: "allMids"})

spot_tokens = Map.new(spot_meta["tokens"], &{&1["index"], &1})

usdc_token =
  spot_meta["tokens"]
  |> Enum.find(&(&1["name"] == "USDC"))
  |> then(&"#{&1["name"]}:#{&1["tokenId"]}")

hype_pair = Enum.find(spot_meta["universe"], &(&1["name"] == "@107"))
hype_sz_dec = spot_tokens[hd(hype_pair["tokens"])]["szDecimals"]
spot_asset = 10_000 + hype_pair["index"]
spot_mid = to_f.(Map.fetch!(mids, "@107"))
spot_px = far_px.(spot_mid, hype_sz_dec, true)
{:ok, spot_sz, spot_ntl} = size_for.(spot_px, hype_sz_dec)

perp_universe = Enum.with_index(perp_meta["universe"])
{btc, btc_idx} = Enum.find(perp_universe, fn {u, _} -> u["name"] == "BTC" end)
perp_sz_dec = btc["szDecimals"]
perp_mid = to_f.(Map.fetch!(mids, "BTC"))
perp_px = far_px.(perp_mid, perp_sz_dec, false)
{:ok, perp_sz, perp_ntl} = size_for.(perp_px, perp_sz_dec)

IO.puts(
  :stderr,
  "spot  HYPE/USDC asset=#{spot_asset} mid=#{spot_mid} px=#{spot_px} sz=#{spot_sz} ntl=#{Float.round(spot_ntl, 2)}"
)

IO.puts(
  :stderr,
  "perp  BTC asset=#{btc_idx} mark=#{perp_mid} px=#{perp_px} sz=#{perp_sz} ntl=#{Float.round(perp_ntl, 2)}\n"
)

if spot_px / spot_mid > 0.85, do: raise("spot price not 15% away")
if perp_px / perp_mid > 0.85, do: raise("perp price not 15% away")

# ===================== Balance accounting =====================

usdc_of = fn user ->
  spot =
    case info.(%{type: "spotClearinghouseState", user: user}) do
      %{"balances" => bs} ->
        bs
        |> Enum.find(&(&1["coin"] == "USDC"))
        |> then(&if(&1, do: to_f.(&1["total"]), else: 0.0))

      _ ->
        0.0
    end

  perp =
    case info.(%{type: "clearinghouseState", user: user}) do
      %{"marginSummary" => %{"accountValue" => v}} -> to_f.(v)
      _ -> 0.0
    end

  {spot, perp}
end

sub_accounts = fn ->
  (info.(%{type: "subAccounts", user: account}) || [])
  |> Enum.filter(&(String.downcase(&1["master"] || "") == String.downcase(account)))
end

total_usdc = fn ->
  {ms, mp} = usdc_of.(account)

  subs =
    for s <- sub_accounts.() do
      {ss, sp} = usdc_of.(s["subAccountUser"])
      ss + sp
    end

  ms + mp + Enum.sum(subs)
end

start_spot_usdc = elem(usdc_of.(account), 0)
start_perp_usdc = elem(usdc_of.(account), 1)
start_total = total_usdc.()
start_orders = info.(%{type: "openOrders", user: account})
start_oids = MapSet.new(start_orders, & &1["oid"])

IO.puts(
  :stderr,
  "START master spot=#{start_spot_usdc} perp=#{start_perp_usdc} total=#{start_total} openOrders=#{length(start_orders)}\n"
)

cancel_all = fn ->
  asset_of =
    Map.merge(
      Map.new(perp_universe, fn {u, i} -> {u["name"], i} end),
      Map.new(spot_meta["universe"], &{&1["name"], 10_000 + &1["index"]})
    )

  stray =
    info.(%{type: "openOrders", user: account})
    |> Enum.reject(&MapSet.member?(start_oids, &1["oid"]))

  if stray != [] do
    cancels = for o <- stray, a = Map.get(asset_of, o["coin"]), do: %{asset: a, oid: o["oid"]}
    Exchange.Cancel.cancel_batch(cancels, mopts)
    length(cancels)
  else
    0
  end
end

guard = fn label ->
  t = total_usdc.()

  if abs(t - start_total) > 0.01 do
    IO.puts(:stderr, "!!! ABORT at #{label}: total USDC #{t} != start #{start_total}")
    n = cancel_all.()

    Smoke.record(
      "ABORT:#{label}",
      :sigfail,
      "balance drift #{t} vs #{start_total}; cancelled #{n}"
    )

    IO.puts(:stderr, "cancelled #{n} order(s); halting")
    System.halt(1)
  end

  t
end

# ===================== 1. Info sanity =====================

step.("info:spotClearinghouseState", master_addr, fn ->
  Info.SpotClearinghouseState.request(account)
end)

step.("info:clearinghouseState", master_addr, fn -> Info.ClearinghouseState.request(account) end)
step.("info:subAccounts", master_addr, fn -> Info.SubAccounts.request(account) end)
step.("info:extraAgents", master_addr, fn -> Info.ExtraAgents.request(account) end)
step.("info:openOrders", master_addr, fn -> Info.OpenOrders.request(account) end)
step.("info:userRole", master_addr, fn -> Info.UserRole.request(account) end)
step.("info:userAbstraction", master_addr, fn -> Info.UserAbstraction.request(account) end)

# ===================== 2. Spot resting-order path (master key) =====================

r1 =
  step.("order:spot limit buy (rests)", master_addr, fn ->
    Exchange.Order.place(Exchange.Order.limit(spot_asset, true, "#{spot_px}", spot_sz), mopts)
  end)

oid1 = Smoke.oid_of(r1)

rmod =
  if oid1 do
    step.("modify (single, new px)", master_addr, fn ->
      px2 = far_px.(spot_mid * 0.99, hype_sz_dec, true)

      Exchange.Modify.modify(
        oid1,
        Exchange.Order.limit(spot_asset, true, "#{px2}", spot_sz),
        mopts
      )
    end)
  else
    skip.("modify (single, new px)", "no resting oid")
    nil
  end

oid1b = Smoke.oid_of(rmod) || oid1

if oid1b do
  step.("cancel:by oid", master_addr, fn -> Exchange.Cancel.cancel(spot_asset, oid1b, mopts) end)
else
  skip.("cancel:by oid", "no resting oid")
end

guard.("after spot order/modify/cancel")

cloid = "0x" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))

rc =
  step.("order:with cloid", master_addr, fn ->
    Exchange.Order.place(
      Exchange.Order.limit(spot_asset, true, "#{spot_px}", spot_sz, cloid: cloid),
      mopts
    )
  end)

case rc do
  {:ok, _} ->
    step.("cancelByCloid", master_addr, fn ->
      Exchange.CancelByCloid.cancel(spot_asset, cloid, mopts)
    end)

  _ ->
    skip.("cancelByCloid", "cloid order not accepted")
end

rf =
  step.("order:for fast cancel", master_addr, fn ->
    Exchange.Order.place(Exchange.Order.limit(spot_asset, true, "#{spot_px}", spot_sz), mopts)
  end)

case Smoke.oid_of(rf) do
  nil ->
    skip.("cancel:batch with fast flag", "no resting oid")

  oid ->
    step.("cancel:batch with fast flag", master_addr, fn ->
      Exchange.Cancel.cancel_batch([%{asset: spot_asset, oid: oid}], mopts ++ [fast: true])
    end)
end

guard.("after cloid/fast cancels")

# ===================== 3. approveBuilderFee (0%) then builder-field order =====

builder = "0xc2e85536528Ae9E9DA3FbE5A4aF4E03358C1CDd9"

step.("approveBuilderFee 0%", master_addr, fn ->
  Exchange.ApproveBuilderFee.request(builder, "0%", mopts)
end)

step.("info:maxBuilderFee (expect 0)", master_addr, fn ->
  Info.MaxBuilderFee.request(account, builder)
end)

rb =
  step.("order:with builder field (fee 0)", master_addr, fn ->
    Exchange.Order.place_batch(
      [Exchange.Order.limit(spot_asset, true, "#{spot_px}", spot_sz)],
      :na,
      mopts ++ [builder: %{builder: String.downcase(builder), fee: 0}]
    )
  end)

case Smoke.oid_of(rb) do
  nil ->
    skip.("cancel:builder order", "not resting")

  oid ->
    step.("cancel:builder order", master_addr, fn ->
      Exchange.Cancel.cancel(spot_asset, oid, mopts)
    end)
end

guard.("after builder order")

# ===================== 4. Class transfers =====================

step.("usdClassTransfer 5 spot->perp", master_addr, fn ->
  Exchange.UsdClassTransfer.request("5", true, mopts)
end)

Process.sleep(1500)
{_, perp_after_xfer} = usdc_of.(account)
IO.puts(:stderr, "  perp accountValue after class transfer: #{perp_after_xfer}")

step.("sendAsset 1 USDC spot->perp (self)", master_addr, fn ->
  Exchange.SendAsset.request(account, "spot", "", usdc_token, "1", mopts)
end)

Process.sleep(1000)

step.("sendAsset 1 USDC perp->spot (self)", master_addr, fn ->
  Exchange.SendAsset.request(account, "", "spot", usdc_token, "1", mopts)
end)

Process.sleep(1500)
guard.("after class transfers")

# ===================== 5. Perp resting order + leverage =====================

step.("updateLeverage BTC cross 5x", master_addr, fn ->
  Exchange.UpdateLeverage.request(btc_idx, 5, true, mopts)
end)

rp =
  step.("order:perp BTC limit buy (rests)", master_addr, fn ->
    Exchange.Order.place(Exchange.Order.limit(btc_idx, true, "#{perp_px}", perp_sz), mopts)
  end)

perp_ok? = Smoke.oid_of(rp) != nil

if perp_ok? do
  step.("cancel:perp order", master_addr, fn ->
    Exchange.Cancel.cancel(btc_idx, Smoke.oid_of(rp), mopts)
  end)
else
  skip.("cancel:perp order", "perp order did not rest")
end

guard.("after perp order")

# --- batch of 2 + batchModify: only viable on perps (spot would need 2x notional
# --- of free USDC, and the account holds only ~14 USDC).
{batch_asset, batch_px, batch_sz, batch_where} =
  if perp_ok? do
    {btc_idx, perp_px, perp_sz, "perp BTC"}
  else
    {spot_asset, spot_px, spot_sz, "spot HYPE/USDC (2nd order will lack funds)"}
  end

px_b =
  if perp_ok?,
    do: far_px.(perp_mid * 0.98, perp_sz_dec, false),
    else: far_px.(spot_mid * 0.98, hype_sz_dec, true)

rbatch =
  step.("order:batch of 2 (#{batch_where})", master_addr, fn ->
    Exchange.Order.place_batch(
      [
        Exchange.Order.limit(batch_asset, true, "#{batch_px}", batch_sz),
        Exchange.Order.limit(batch_asset, true, "#{px_b}", batch_sz)
      ],
      :na,
      mopts
    )
  end)

batch_oids = Smoke.oids_of(rbatch)

if batch_oids != [] do
  px_c =
    if perp_ok?,
      do: far_px.(perp_mid * 0.97, perp_sz_dec, false),
      else: far_px.(spot_mid * 0.97, hype_sz_dec, true)

  step.("batchModify", master_addr, fn ->
    Exchange.BatchModify.modify_batch(
      for o <- batch_oids do
        %{oid: o, order: Exchange.Order.limit(batch_asset, true, "#{px_c}", batch_sz)}
      end,
      mopts
    )
  end)
else
  skip.("batchModify", "no resting orders from batch")
end

Process.sleep(500)

live =
  info.(%{type: "openOrders", user: account})
  |> Enum.reject(&MapSet.member?(start_oids, &1["oid"]))

if live != [] do
  step.("cancel:batch with fast flag (cleanup)", master_addr, fn ->
    Exchange.Cancel.cancel_batch(
      Enum.map(live, &%{asset: batch_asset, oid: &1["oid"]}),
      mopts ++ [fast: true]
    )
  end)
else
  skip.("cancel:batch with fast flag (cleanup)", "nothing resting")
end

guard.("after batch orders")

# Return the class-transferred USDC to spot now that the perp tests are done.
step.("usdClassTransfer 5 perp->spot", master_addr, fn ->
  Exchange.UsdClassTransfer.request("5", false, mopts)
end)

Process.sleep(1500)
guard.("after perp->spot class transfer")

# ===================== 6. approveAgent + agent-key order =====================

agent_key = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
agent_addr = Signer.derive_address(agent_key)

step.("approveAgent 'elixir-smoke'", master_addr, fn ->
  Exchange.ApproveAgent.approve(agent_addr, mopts ++ [agent_name: "elixir-smoke"])
end)

Process.sleep(1000)

agents = info.(%{type: "extraAgents", user: account}) || []

agent_listed? =
  Enum.any?(agents, &(String.downcase(&1["address"] || "") == String.downcase(agent_addr)))

Smoke.record(
  "verify:extraAgents contains agent",
  if(agent_listed?, do: :ok, else: :rule),
  inspect(agents)
)

if agent_listed? do
  aopts = [private_key: agent_key]

  ra =
    step.("order:spot limit with AGENT key", agent_addr, fn ->
      Exchange.Order.place(Exchange.Order.limit(spot_asset, true, "#{spot_px}", spot_sz), aopts)
    end)

  case Smoke.oid_of(ra) do
    nil ->
      skip.("cancel:agent order", "agent order did not rest")

    oid ->
      step.("cancel:agent order (agent key)", agent_addr, fn ->
        Exchange.Cancel.cancel(spot_asset, oid, aopts)
      end)
  end
else
  skip.("order:spot limit with AGENT key", "agent not listed in extraAgents")
  skip.("cancel:agent order (agent key)", "agent not listed in extraAgents")
end

guard.("after agent order")

# ===================== 7. Sub-account =====================

existing = sub_accounts.()

sub_addr =
  case existing do
    [s | _] ->
      Smoke.record(
        "createSubAccount 'elixir-smoke'",
        :skip,
        "sub-account already exists: #{s["subAccountUser"]}"
      )

      s["subAccountUser"]

    [] ->
      r =
        step.("createSubAccount 'elixir-smoke'", master_addr, fn ->
          Exchange.CreateSubAccount.request("elixir-smoke", mopts)
        end)

      case r do
        {:ok, resp} ->
          get_in(resp, ["response", "data"])
          |> then(fn d -> if is_binary(d), do: d, else: nil end)

        _ ->
          nil
      end
  end

sub_addr =
  sub_addr ||
    (
      Process.sleep(1500)
      sub_accounts.() |> List.first() |> then(&(&1 && &1["subAccountUser"]))
    )

if sub_addr do
  IO.puts(:stderr, "  sub-account: #{sub_addr}")

  step.("usdSend 2 USDC -> own sub-account", master_addr, fn ->
    Exchange.UsdSend.request(sub_addr, "2", mopts)
  end)

  Process.sleep(2000)
  IO.puts(:stderr, "  sub spot/perp USDC: #{inspect(usdc_of.(sub_addr))}")
  guard.("after usdSend to sub")

  step.("subAccountTransfer 2 USDC sub->master", master_addr, fn ->
    Exchange.SubAccountTransfer.request(sub_addr, false, 2_000_000, mopts)
  end)

  step.("subAccountSpotTransfer 2 USDC sub->master", master_addr, fn ->
    Exchange.SubAccountSpotTransfer.request(sub_addr, false, usdc_token, "2", mopts)
  end)

  Process.sleep(1500)
  {sub_spot, _} = usdc_of.(sub_addr)

  if sub_spot > 0.0 do
    step.("sendAsset fromSubAccount 2 USDC -> master", master_addr, fn ->
      Exchange.SendAsset.request(
        account,
        "spot",
        "spot",
        usdc_token,
        :erlang.float_to_binary(sub_spot, decimals: 6),
        mopts ++ [from_sub_account: sub_addr]
      )
    end)
  else
    skip.("sendAsset fromSubAccount 2 USDC -> master", "sub-account spot USDC already 0")
  end

  Process.sleep(1500)
  guard.("after sub-account recovery")

  step.("subAccountModify rename -> elixir-smoke2", master_addr, fn ->
    Exchange.SubAccountModify.request("elixir-smoke2", mopts ++ [sub_account_user: sub_addr])
  end)

  step.("subAccountModify rename -> elixir-smoke", master_addr, fn ->
    Exchange.SubAccountModify.request("elixir-smoke", mopts ++ [sub_account_user: sub_addr])
  end)
else
  for n <-
        ~w(usdSend subAccountTransfer subAccountSpotTransfer sendAsset:fromSubAccount subAccountModify) do
    skip.("#{n}", "no sub-account available")
  end
end

# ===================== 8. Misc state actions =====================

step.("scheduleCancel (+60s)", master_addr, fn ->
  Exchange.ScheduleCancel.request(System.system_time(:millisecond) + 60_000, mopts)
end)

step.("scheduleCancel (clear)", master_addr, fn -> Exchange.ScheduleCancel.request(nil, mopts) end)

step.("reserveRequestWeight", master_addr, fn ->
  Exchange.ReserveRequestWeight.request(1, mopts)
end)

step.("noop", master_addr, fn -> Exchange.Noop.request(mopts) end)

step.("setDisplayName 'hl-elixir-smoke'", master_addr, fn ->
  Exchange.SetDisplayName.request("hl-elixir-smoke", mopts)
end)

step.("setDisplayName (clear)", master_addr, fn -> Exchange.SetDisplayName.request("", mopts) end)

step.("evmUserModify usingBigBlocks(true)", master_addr, fn ->
  Exchange.EvmUserModify.request(true, mopts)
end)

step.("evmUserModify usingBigBlocks(false)", master_addr, fn ->
  Exchange.EvmUserModify.request(false, mopts)
end)

step.("spotUser optOutOfSpotDusting(true)", master_addr, fn ->
  Exchange.SpotUser.toggle_spot_dusting(true, mopts)
end)

step.("spotUser optOutOfSpotDusting(false)", master_addr, fn ->
  Exchange.SpotUser.toggle_spot_dusting(false, mopts)
end)

step.("userSetAbstraction(unifiedAccount) [current value]", master_addr, fn ->
  Exchange.UserSetAbstraction.request(account, "unifiedAccount", mopts)
end)

step.("userDexAbstraction(true)", master_addr, fn ->
  Exchange.UserDexAbstraction.request(account, true, mopts)
end)

step.("userDexAbstraction(false)", master_addr, fn ->
  Exchange.UserDexAbstraction.request(account, false, mopts)
end)

skip.("userPortfolioMargin", "SKIPPED by instruction — state change with margin implications")
skip.("withdraw3", "BLOCKED — moves value off the exchange")
skip.("sendToEvmWithData", "BLOCKED")

skip.(
  "vault* / staking (tokenDelegate, cDeposit, cWithdraw) / referral / deploy / borrowLend / outcome / claimRewards",
  "BLOCKED by instruction"
)

skip.("IOC / market / trigger orders", "BLOCKED by hard rules")

# ===================== 9. Reconciliation =====================

IO.puts(:stderr, "\n=== reconciliation ===")
n_cancelled = cancel_all.()
if n_cancelled > 0, do: IO.puts(:stderr, "cleanup cancelled #{n_cancelled} stray order(s)")
Process.sleep(2500)

{end_spot_usdc, end_perp_usdc} = usdc_of.(account)
end_subs = sub_accounts.()
sub_bals = for s <- end_subs, do: {s["name"], s["subAccountUser"], usdc_of.(s["subAccountUser"])}
end_total = total_usdc.()
end_orders = info.(%{type: "openOrders", user: account})
end_positions = info.(%{type: "clearinghouseState", user: account})["assetPositions"]
end_agents = info.(%{type: "extraAgents", user: account}) || []

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
    "#{String.pad_trailing(name, 52)} | #{String.pad_trailing(label, 7)} | #{String.slice(to_string(msg), 0, 260)}"
  )
end

IO.puts("\n==================== BALANCES ====================")
IO.puts("master spot USDC : start=#{start_spot_usdc}  end=#{end_spot_usdc}")
IO.puts("master perp USDC : start=#{start_perp_usdc}  end=#{end_perp_usdc}")
IO.puts("sub-accounts     : #{inspect(sub_bals)}")

IO.puts(
  "TOTAL USDC       : start=#{start_total}  end=#{end_total}  delta=#{fmt.(end_total - start_total, 6)}"
)

IO.puts("open orders      : start=#{length(start_orders)}  end=#{length(end_orders)}")
IO.puts("positions        : #{inspect(end_positions)}")

IO.puts("\n==================== LEFTOVERS ====================")
IO.puts("agent (remove manually): #{agent_addr}")
IO.puts("extraAgents now: #{inspect(end_agents)}")
IO.puts("sub-accounts now: #{inspect(Enum.map(end_subs, &{&1["name"], &1["subAccountUser"]}))}")
IO.puts("BTC leverage set to cross 5x")

IO.puts("\ncounts: #{inspect(Smoke.results() |> Enum.frequencies_by(fn {_, c, _} -> c end))}")
