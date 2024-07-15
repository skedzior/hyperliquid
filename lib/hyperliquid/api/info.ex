defmodule Hyperliquid.Api.Info do
  @moduledoc """
  Info endpoints.
  """
  use Hyperliquid.Api, context: "info"

  def user_vault_equities(user_address) do
    post(%{type: "userVaultEquities", user: user_address})
  end

  # only for testnet
  def eth_faucet(user_address) do
    post(%{type: "ethFaucet", user: user_address})
  end

  def user_rate_limit(user_address) do
    post(%{type: "userRateLimit", user: user_address})
  end

  def meta do
    post(%{type: "meta"})
  end

  def meta_and_asset_ctxs do
    post(%{type: "metaAndAssetCtxs"})
  end

  def clearinghouse_state(user_address) do
    post(%{type: "clearinghouseState", user: user_address})
  end

  def spot_meta do
    post(%{type: "spotMeta"})
  end

  def spot_meta_and_asset_ctxs do
    post(%{type: "spotMetaAndAssetCtxs"})
  end

  def spot_clearinghouse_state(user_address) do
    post(%{type: "spotClearinghouseState", user: user_address})
  end

  def leaderboard do
    post(%{type: "leaderboard"})
  end

  def all_mids do
    post(%{type: "allMids"})
  end

  def candle_snapshot(coin, interval, start_time, end_time) do
    post(%{
      type: "candleSnapshot",
      req: %{coin: coin, interval: interval, startTime: start_time, endTime: end_time}
    })
  end

  def l2_book(coin) do
    post(%{type: "l2Book", coin: coin})
  end

  def user_funding(user_address, start_time, end_time) do
    post(%{
      type: "userFunding",
      user: user_address,
      startTime: start_time,
      endTime: end_time
    })
  end

  def funding_history(coin, start_time, end_time) do
    post(%{type: "fundingHistory", coin: coin, startTime: start_time, endTime: end_time})
  end

  def get_orders(user_address) do
    post(%{type: "openOrders", user: user_address})
  end

  def get_orders_fe(user_address) do
    post(%{type: "frontendOpenOrders", user: user_address})
  end

  def user_fees(user_address) do
    post(%{type: "userFees", user: user_address})
  end

  def order_by_id(user_address, id) do
    # id = oid | cloid
    post(%{type: "orderStatus", user: user_address, oid: id})
  end

  def referral_state(user_address) do
    post(%{type: "referral", user: user_address})
  end

  def sub_accounts(user_address) do
    post(%{type: "subAccounts", user: user_address})
  end

  def agents(user_address) do
    post(%{type: "extraAgents", user: user_address})
  end

  def portfolio(user_address) do
    post(%{type: "portfolio", user: user_address})
  end

  def predicted_fundings do
    post(%{type: "predictedFundings"})
  end

  def is_vip(user_address) do
    post(%{type: "isVip", user: user_address})
  end

  def vaults(user_address) do
    post(%{type: "vaults", user: user_address})
  end

  def user_twap_slice_fills(user_address) do
    post(%{type: "userTwapSliceFills", user: user_address})
  end

  def user_web_data(user_address) do
    post(%{type: "webData2", user: user_address})
  end

  def user_non_funding_ledger_updates(user_address) do
    post(%{type: "userNonFundingLedgerUpdates", user: user_address})
  end

  def user_fills(user_address) do
    post(%{type: "userFills", user: user_address})
  end

  def tvl_breakdown do
    post(%{type: "tvlBreakdown"})
  end
end
