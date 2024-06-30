defmodule Hyperliquid.Api.Info do
  use Hyperliquid.Api, context: "info"

  def user_vault_equities(user_address) do
    post(%{type: "userVaultEquities", user: user_address})
  end

  #TODO: only for testnet
  def eth_faucet(user_address) do
    # response = Meta
    post(%{type: "ethFaucet", user: user_address})
  end

  def user_rate_limit(user_address) do
    post(%{type: "userRateLimit", user: user_address})
  end

  def meta do
    # response = Meta
    post(%{type: "meta"})
  end

  def meta_and_asset_ctxs do
    # response = TODO
    post(%{type: "metaAndAssetCtxs"})
  end

  def clearinghouse_state(user_address) do
    # response = ClearingState
    post(%{type: "clearinghouseState", user: user_address})
  end

  def spot_meta do
    # response = SpotMeta
    post(%{type: "spotMeta"})
  end

  def spot_meta_and_asset_ctxs do
    # description: Fetch metadata and context information for actively trading assets
    # response = TODO
    post(%{type: "spotMetaAndAssetCtxs"})
  end

  def spot_clearinghouse_state(user_address) do
    # description: Fetch a user's state
    # response = SpotClearingState
    post(%{type: "spotClearinghouseState", user: user_address})
  end

  def leaderboard do
    # response = TODO
    post(%{type: "leaderboard"})
  end

  def all_mids do
    # response = TODO
    post(%{type: "allMids"})
  end

  def candle_snapshot(coin, interval, start_time, end_time) do
    # description: Fetch candle snapshot for a given coin
    # response = Candle
    post(%{
      type: "candleSnapshot",
      req: %{coin: coin, interval: interval, startTime: start_time, endTime: end_time}
    })
  end

  def l2_book(coin) do
    # description: Fetch L2 book snapshot for a given coin
    # response = L2Book
    post(%{type: "l2Book", coin: coin})
  end

  def user_funding(user_address, start_time, end_time) do
    # description: Fetch a user's funding history
    # response = UserFunding
    post(%{
      type: "userFunding",
      user: user_address,
      startTime: start_time,
      endTime: end_time
    })
  end

  def funding_history(coin, start_time, end_time) do
    # description: Fetch funding history
    # response = HistoricalFunding
    post(%{type: "fundingHistory", coin: coin, startTime: start_time, endTime: end_time})
  end

  def get_orders(user_address) do
    # response = Order
    post(%{type: "openOrders", user: user_address})
  end

  def get_orders_fe(user_address) do
    # response = TODO
    post(%{type: "frontendOpenOrders", user: user_address})
  end

  def user_fees(user_address) do
    # reponse = ReferralData
    post(%{type: "userFees", user: user_address})
  end

  def order_by_id(user_address, id) do
    # response = TODO
    # id = oid | cloid
    post(%{type: "orderStatus", user: user_address, oid: id})
  end

  # def order_by_cloid(user_address, cloid) do
  #   # response = TODO
  #   post(%{type: "orderStatus", user: user_address, oid: cloid})
  # end

  def referral_state(user_address) do
    # response = ReferralState
    post(%{type: "referral", user: user_address})
  end

  def sub_accounts(user_address) do
    # response = [SubAccount]
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
end
