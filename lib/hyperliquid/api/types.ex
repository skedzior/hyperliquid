defmodule Hyperliquid.Api.Types do
  import Hyperliquid.Utils

  # TESTED
  defmodule ReferralState do
    defmodule ReferredBy do
      @type t :: %__MODULE__{
              code: String.t(),
              referrer: String.t()
            }
      defstruct [:code, :referrer]
    end

    defmodule ReferrerState do
      defmodule Data do
        @type t :: %__MODULE__{
                code: String.t(),
                referralStates: list()
              }
        defstruct [:code, :referralStates]
      end

      @type t :: %__MODULE__{
              data: Data.t(),
              stage: String.t()
            }
      defstruct [:data, :stage]
    end

    @type t :: %__MODULE__{
            claimedRewards: String.t(),
            cumVlm: String.t(),
            referredBy: ReferredBy.t(),
            referrerState: ReferrerState.t(),
            rewardHistory: list(),
            unclaimedRewards: String.t()
          }
    defstruct [
      :claimedRewards,
      :cumVlm,
      :referredBy,
      :referrerState,
      :rewardHistory,
      :unclaimedRewards
    ]
  end
  # TESTED
  defmodule ReferralData do
    defmodule DailyUserVolume do
      @type t :: %__MODULE__{
              date: String.t(),
              exchange: String.t(),
              userAdd: String.t(),
              userCross: String.t()
            }
      defstruct [:date, :exchange, :userAdd, :userCross]
    end

    defmodule FeeSchedule do
      defmodule Tiers do
        defmodule MM do
          @type t :: %__MODULE__{
                  add: String.t(),
                  makerFractionCutoff: String.t()
                }
          defstruct [:add, :makerFractionCutoff]
        end

        defmodule VIP do
          @type t :: %__MODULE__{
                  add: String.t(),
                  cross: String.t(),
                  ntlCutoff: String.t()
                }
          defstruct [:add, :cross, :ntlCutoff]
        end
      end

      @type t :: %__MODULE__{
              add: String.t(),
              cross: String.t(),
              referralDiscount: String.t(),
              tiers: %{
                mm: [Tiers.MM.t()],
                vip: [Tiers.VIP.t()]
              }
            }
      defstruct [:add, :cross, :referralDiscount, :tiers]
    end

    @type t :: %__MODULE__{
            activeReferralDiscount: String.t(),
            dailyUserVlm: [DailyUserVolume.t()],
            feeSchedule: FeeSchedule.t(),
            userAddRate: String.t(),
            userCrossRate: String.t()
          }
    defstruct [
      :activeReferralDiscount,
      :dailyUserVlm,
      :feeSchedule,
      :userAddRate,
      :userCrossRate
    ]
  end

  defmodule Side do
    @type t :: :A | :B

    @spec to_string(t) :: String.t()
    def to_string(:A), do: "Sell"
    def to_string(:B), do: "Buy"
  end

  # defmodule Position do
  #   defstruct [:coin, :entry_px, :leverage, :liquidation_px, :margin_used, :max_leverage, :max_trade_szs, :position_value, :return_on_equity, :szi, :unrealized_pnl]
  # end

  defmodule AssetPosition do
    defstruct [:position, :type]
  end

  # defmodule OpenOrder do
  #   defstruct [:coin, :limit_px, :oid, :orig_sz, :reduce_only, :side, :sz, :timestamp]
  # end

  defmodule Fill do
    @type t :: %__MODULE__{
            coin: String.t(),
            px: String.t(),
            sz: String.t(),
            side: Side.t(),
            time: integer(),
            startPosition: String.t(),
            dir: String.t(),
            closedPnl: String.t(),
            hash: String.t(),
            oid: integer(),
            crossed: boolean()
          }
    defstruct [
      :coin, :px, :sz, :side, :time, :startPosition, :dir, :closedPnl, :hash, :oid, :crossed
    ]
  end

  defmodule UserFill do
    @type t :: %__MODULE__{
            coin: String.t(),
            px: String.t(),
            sz: String.t(),
            side: String.t(),
            time: integer(),
            startPosition: String.t(),
            dir: String.t(),
            closedPnl: String.t(),
            hash: String.t(),
            oid: integer(),
            crossed: boolean(),
            fee: String.t(),
            tid: integer()
          }
    defstruct [:coin, :px, :sz, :side, :time, :startPosition, :dir, :closedPnl, :hash, :oid, :crossed, :fee, :tid]
  end

  defmodule Liquidation do
    @type t :: %__MODULE__{
            lid: integer(),
            liquidator: String.t(),
            liquidated_user: String.t(),
            liquidated_ntl_pos: String.t(),
            liquidated_account_value: String.t()
          }
    defstruct [:lid, :liquidator, :liquidated_user, :liquidated_ntl_pos, :liquidated_account_value]
  end

  # TESTED
  defmodule Order do
    @type t :: %__MODULE__{
            coin: String.t(),
            side: String.t(),
            limitPx: String.t(),
            sz: String.t(),
            oid: integer(),
            timestamp: integer(),
            origSz: String.t(),
            cloid: String.t() | nil
          }
    defstruct [:coin, :side, :limitPx, :sz, :oid, :timestamp, :origSz, :cloid]
  end

  # TESTED
  defmodule HistoricalFunding do
    @type t :: %__MODULE__{
      time: integer(),
      coin: String.t(),
      premium: String.t(),
      fundingRate: String.t()
    }
    defstruct [:coin, :fundingRate, :premium, :time]
  end

  defmodule OrderStatus do
    @type t :: %__MODULE__{
            order: Order.t(),
            status: String.t(),
            statusTimestamp: integer()
          }
    defstruct [:order, :status, :statusTimestamp]
  end

  # TESTED
  defmodule UserFundingDelta do
    @type t :: %__MODULE__{
            time: integer(),
            coin: String.t(),
            usdc: String.t(),
            szi: String.t(),
            fundingRate: String.t(),
            nSamples: any()
          }
    defstruct [:time, :coin, :usdc, :szi, :fundingRate, :nSamples]
  end

  # TESTED
  defmodule UserFunding do
    @type t :: %__MODULE__{
            time: integer(),
            hash: String.t(),
            delta: UserFundingDelta.t()
          }
    defstruct [:time, :hash, :delta]
  end

  defmodule Trade do
    @type t :: %__MODULE__{
            coin: String.t(),
            side: String.t(),
            px: String.t(),
            sz: String.t(),
            hash: String.t(),
            time: integer(),
            tid: integer() | nil
          }
    defstruct [:coin, :side, :px, :sz, :hash, :time, :tid]
  end

  # TESTED
  defmodule SpotAssetInfo do
    @type t :: %__MODULE__{
            name: String.t(),
            tokens: [integer()]
          }
    defstruct [:name, :tokens]
  end

  # TESTED
  defmodule SpotTokenInfo do
    @type t :: %__MODULE__{
            name: String.t(),
            szDecimals: integer(),
            weiDecimals: integer()
          }
    defstruct [:name, :szDecimals, :weiDecimals]
  end

  # TESTED
  defmodule SpotMeta do
    @type t :: %__MODULE__{
            universe: [SpotAssetInfo.t()],
            tokens: [SpotTokenInfo.t()]
          }
    defstruct [:universe, :tokens]
  end

  # TESTED
  defmodule AssetInfo do
    @type t :: %__MODULE__{
            name: String.t(),
            szDecimals: integer()
          }
    defstruct [:name, :szDecimals]
  end

  # TESTED
  defmodule Meta do
    @type t :: %__MODULE__{
            universe: [AssetInfo.t()]
          }
    defstruct [:universe]
  end

  # TESTED
  defmodule L2Level do
    @type t :: %__MODULE__{
            px: String.t(),
            sz: String.t(),
            n: integer()
          }
    defstruct [:px, :sz, :n]
  end

  # TESTED
  defmodule L2Book do
    @type t :: %__MODULE__{
            coin: String.t(),
            levels: [[L2Level.t()]],
            time: integer()
          }
    defstruct [:coin, :levels, :time]
  end

  defmodule L2BookMsg do
    @type t :: %__MODULE__{
            channel: String.t(),
            coin: String.t(),
            levels: {[L2Level.t()]},
            time: integer()
          }
    defstruct [:coin, :levels, :time, channel: "l2Book"]
  end

  # TESTED
  defmodule Candle do
    @type t :: %__MODULE__{
            t: integer(),
            T: integer(),
            s: String.t(),
            i: String.t(),
            o: float(),
            c: float(),
            h: float(),
            l: float(),
            v: float(),
            n: integer()
          }
    defstruct [:t, :T, :s, :i, :o, :c, :h, :l, :v, :n]
  end

  defmodule AllMidsSubscription do
    defstruct [:type]
  end

  defmodule L2BookSubscription do
    defstruct [:type, :coin]
  end

  defmodule TradesSubscription do
    defstruct [:type, :coin]
  end

  defmodule UserEventsSubscription do
    defstruct [:type, :user]
  end

  defmodule WebData do
    defstruct [:type, :user]
  end

  defmodule Subscription do
    @type t :: %AllMidsSubscription{} | %L2BookSubscription{} | %TradesSubscription{} | %UserEventsSubscription{} | %WebData{}
  end

  defmodule Channel do
    defstruct [:channel]
  end

  defmodule AllMidsData do
    defstruct [:mids]
  end

  defmodule AllMidsMsg do
    defstruct [:channel, :data]
  end

  defmodule TradesMsg do
    defstruct [:channel, :data]
  end

  defmodule UserEventsData do
    defstruct [:fills]
  end

  defmodule UserEventsMsg do
    defstruct [:channel, :data]
  end

  defmodule L2BookMsg do
    defstruct [:channel, :data]
  end

  defmodule WsMsg do
    @type t :: %AllMidsMsg{} | %L2BookMsg{} | %TradesMsg{} | %UserEventsMsg{}
  end

  defmodule Tif do
    @type t :: :Alo | :Ioc | :Gtc | :FrontendMarket

    @spec to_string(t) :: String.t()
    def to_string(:Alo), do: "Alo"
    def to_string(:Ioc), do: "Ioc"
    def to_string(:Gtc), do: "Gtc"
    def to_string(:FrontendMarket), do: "FrontendMarket"
  end

  defmodule Tpsl do
    @type t :: :tp | :sl

    @spec to_string(t) :: String.t()
    def to_string(:tp), do: "tp"
    def to_string(:sl), do: "sl"
  end

  defmodule LimitOrderType do
    defstruct [:tif]
  end

  # defmodule TriggerOrderType do
  #   defstruct [:trigger_px, :is_market, :tpsl]
  # end

  # defmodule TriggerOrderTypeWire do
  #   defstruct [:trigger_px, :is_market, :tpsl]
  # end

  # defmodule Order do
  #   defstruct [:asset, :is_buy, :limit_px, :sz, :reduce_only]
  # end

  defmodule OrderType do
    defstruct [:limit, :trigger]

    def to_list(%{limit: limit} = _order_type) do
      case limit.tif do
        "Gtc" -> [2, 0]
        "Alo" -> [1, 0]
        "Ioc" -> [3, 0]
        "FrontendMarket" -> [8, 0]
      end
    end

    def to_list(%{trigger: trigger} = _order_type) do
      case {trigger.is_market, trigger.tpsl} do
        {true, "tp"} -> [4, trigger.trigger_px]
        {false, "tp"} -> [5, trigger.trigger_px]
        {true, "sl"} -> [6, trigger.trigger_px]
        {false, "sl"} -> [7, trigger.trigger_px]
      end
    end
  end

  defmodule OrderWire do
    defstruct [:a, :b, :p, :s, :r, :t, c: nil]

    @doc """
    Creates a new OrderWire struct.
    """
    def new(asset, is_buy, limit_px, sz, reduce_only, trigger, cloid \\ nil) do
      %__MODULE__{
        a: asset,
        b: is_buy,
        p: limit_px,
        s: sz,
        r: reduce_only,
        t: trigger,
        c: cloid
      }
    end

    @doc """
    Converts price and size to string if they are integer or float, and removes nil values from the struct.
    """
    def purify(%__MODULE__{} = order_wire) do
      order_wire
      |> numbers_to_strings([:p, :s])
      |> Map.from_struct()
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()
    end
  end

  defmodule OrderSpec do
    defstruct [:order, :order_type]
  end

  defmodule OrderRequest do
    defstruct [:coin, :is_buy, :sz, :limit_px, :order_type, :reduce_only]

    # def to_params(order_request) do
    #   asset_map = asset_map()
    #   [
    #     asset_map[order_request.coin],
    #     order_request.is_buy,
    #     float_to_int_for_hashing(order_request.limit_px),
    #     float_to_int_for_hashing(order_request.sz),
    #     order_request.reduce_only
    #   ]
    # end

    # # used to override actual asset_map, good for testing or passing your own way to keep state
    # def to_params(order_request, asset) do
    #   [
    #     asset,
    #     order_request.is_buy,
    #     float_to_int_for_hashing(order_request.limit_px),
    #     float_to_int_for_hashing(order_request.sz),
    #     order_request.reduce_only
    #   ]
    # end
  end
end
