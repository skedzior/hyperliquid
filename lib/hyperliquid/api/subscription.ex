defmodule Hyperliquid.Api.Subscription do
  @moduledoc """
  Subscriptions and related helper methods.
  """
  alias Hyperliquid.Utils

  @type subscription :: %{
    type: String.t(),
    user: String.t() | nil,
    coin: String.t() | nil,
    interval: String.t() | nil
  }

  @type subscription_message :: %{
    method: String.t(),
    subscription: subscription()
  }

  # topics
  def general_topics, do: ["allMids", "explorerBlock", "explorerTxs"]

  def coin_topics, do: ["candle", "l2Book", "trades", "activeAssetCtx"]

  def user_topics,
    do: [
      "orderUpdates",
      "userFills",
      "userEvents",
      "userFundings",
      "notification",
      "webData2",
      "userNonFundingLedgerUpdates",
      "userHistoricalOrders",
      "userTwapHistory",
      "userTwapSliceFills",
      "activeAssetData"
    ]

  def topics, do: Enum.concat([general_topics(), coin_topics(), user_topics()])

  # GENERAL #
  def all_mids, do: %{type: "allMids"}

  def explorer_block, do: %{type: "explorerBlock"}

  def explorer_txs, do: %{type: "explorerTxs"}

  # COIN #
  def candle(coin, interval), do: %{type: "candle", coin: coin, interval: interval}

  def l2_book(coin, sig_figs \\ 5, mantissa \\ nil), do: %{type: "l2Book", coin: coin, nSigFigs: sig_figs, mantissa: mantissa}

  def trades(coin), do: %{type: "trades", coin: coin}

  def active_asset_ctx(coin), do: %{type: "activeAssetCtx", coin: coin}

  # USER #
  def order_updates(user), do: %{type: "orderUpdates", user: user}

  def user_events(user), do: %{type: "userEvents", user: user}

  def user_fills(user), do: %{type: "userFills", user: user}

  def user_fundings(user), do: %{type: "userFundings", user: user}

  def notification(user), do: %{type: "notification", user: user}

  def web_data(user), do: %{type: "webData2", user: user}

  def user_non_funding_ledger_updates(user), do: %{type: "userNonFundingLedgerUpdates", user: user}

  def user_historical_orders(user), do: %{type: "userHistoricalOrders", user: user}

  def user_twap_history(user), do: %{type: "userTwapHistory", user: user}

  def user_twap_slice_fills(user), do: %{type: "userTwapSliceFills", user: user}

  def active_asset_data(user, coin), do: %{type: "activeAssetData", user: user, coin: coin}

  ###### helpers ########

  def make_user_subs(user),
    do: [
      notification(user),
      user_fills(user),
      user_non_funding_ledger_updates(user),
      user_twap_slice_fills(user),
      user_twap_history(user),
      user_historical_orders(user),
      user_fundings(user)
    ]

  def make_user_subs(user, coin), do: make_user_subs(user) ++ [active_asset_data(user, coin)]

  def get_subject(value) when is_map(value), do: sub_to_subject(value)
  def get_subject(value), do: topic_to_subject(value)

  defp topic_to_subject(topic) do
    cond do
      Enum.member?(user_topics(), topic) -> :user
      Enum.member?(coin_topics(), topic) -> :coin
      true -> :info
    end
  end

  defp sub_to_subject(sub) do
    cond do
      Map.has_key?(sub, :user) -> :user
      Map.has_key?(sub, :coin) -> :coin
      true -> :info
    end
  end

  def to_key(%{"type" => _} = sub), do: Utils.atomize_keys(sub) |> to_key()

  def to_key(%{type: type} = sub) do
    cond do
      type == "activeAssetData" -> {sub.user, type, sub.coin}
      Map.has_key?(sub, :user) -> {sub.user, type}
      Map.has_key?(sub, :interval) -> {sub.coin, type, sub.interval}
      Map.has_key?(sub, :coin) -> {sub.coin, type}
      true -> type
    end
  end

  def to_message(sub, sub? \\ true)
  def to_message(sub, true), do: %{method: "subscribe", subscription: sub}
  def to_message(sub, false), do: %{method: "unsubscribe", subscription: sub}

  def to_encoded_message(sub, sub? \\ true), do: to_message(sub, sub?) |> Jason.encode!()
end
