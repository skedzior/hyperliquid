defmodule Hyperliquid.Api.Exchange.Order do
  @moduledoc """
  Place orders on Hyperliquid.

  Supports limit orders, trigger orders (stop-loss/take-profit), and batch ordering.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  require Logger

  alias Hyperliquid.{Cache, Config, Signer, Utils}
  alias Hyperliquid.Api.ActionEncoder
  alias Hyperliquid.Utils.Format
  alias Hyperliquid.Transport.Http

  @default_slippage 0.05

  # ===================== Coin-Based Order Builders =====================

  @doc """
  Build a limit order using coin symbol.

  Automatically looks up asset index and formats price/size.

  ## Parameters
    - `coin`: Coin symbol (e.g., "BTC", "ETH", "HYPE/USDC")
    - `is_buy`: true for buy, false for sell
    - `limit_px`: Limit price
    - `sz`: Size
    - `opts`: Optional parameters (see `limit/5`)

  ## Examples

      Order.limit_order("BTC", true, 50000.0, 0.1)
      Order.limit_order("ETH", false, "3500.5", "1.5", tif: "Ioc")
  """
  @spec limit_order(
          String.t(),
          boolean(),
          number() | String.t(),
          number() | String.t(),
          keyword()
        ) ::
          limit_order() | {:error, term()}
  def limit_order(coin, is_buy, limit_px, sz, opts \\ []) do
    with {:ok, asset, sz_decimals, is_spot} <- resolve_coin(coin) do
      formatted_price = Format.format_price(limit_px, sz_decimals, perp: not is_spot)
      formatted_size = Format.format_size(sz, sz_decimals)

      limit(asset, is_buy, formatted_price, formatted_size, opts)
    end
  end

  @doc """
  Build a trigger order using coin symbol.

  Automatically looks up asset index and formats price/size.

  ## Parameters
    - `coin`: Coin symbol
    - `is_buy`: true for buy, false for sell
    - `limit_px`: Limit price
    - `sz`: Size
    - `trigger_px`: Trigger price
    - `opts`: Optional parameters (see `trigger/6`)

  ## Examples

      # Stop-loss
      Order.trigger_order("BTC", false, 48000, 0.1, 49000, tpsl: "sl")

      # Take-profit
      Order.trigger_order("BTC", false, 56000, 0.1, 55000, tpsl: "tp")
  """
  @spec trigger_order(
          String.t(),
          boolean(),
          number() | String.t(),
          number() | String.t(),
          number() | String.t(),
          keyword()
        ) ::
          trigger_order() | {:error, term()}
  def trigger_order(coin, is_buy, limit_px, sz, trigger_px, opts \\ []) do
    with {:ok, asset, sz_decimals, is_spot} <- resolve_coin(coin) do
      formatted_price = Format.format_price(limit_px, sz_decimals, perp: not is_spot)
      formatted_size = Format.format_size(sz, sz_decimals)
      formatted_trigger = Format.format_price(trigger_px, sz_decimals, perp: not is_spot)

      trigger(asset, is_buy, formatted_price, formatted_size, formatted_trigger, opts)
    end
  end

  @doc """
  Build a market order using coin symbol.

  Automatically looks up asset index, mid price, and formats size.

  ## Parameters
    - `coin`: Coin symbol
    - `is_buy`: true for buy, false for sell
    - `sz`: Size
    - `opts`: Optional parameters
      - `:slippage` - Slippage percentage (default: 0.05 = 5%)
      - `:slippage_price` - Explicit far price (overrides automatic calculation)
      - `:reduce_only` - Only reduce position
      - `:cloid` - Client order ID

  ## Examples

      Order.market_order("BTC", true, 0.1)
      Order.market_order("ETH", false, 1.5, slippage: 0.03)
  """
  @spec market_order(String.t(), boolean(), number() | String.t(), keyword()) ::
          limit_order() | {:error, term()}
  def market_order(coin, is_buy, sz, opts \\ []) do
    with {:ok, asset, sz_decimals, is_spot} <- resolve_coin(coin) do
      formatted_size = Format.format_size(sz, sz_decimals)

      slippage_price =
        case Keyword.get(opts, :slippage_price) do
          nil ->
            slippage = Keyword.get(opts, :slippage, @default_slippage)

            case Cache.get_mid(coin) do
              nil ->
                raise ArgumentError,
                      "Mid price not found for #{coin}. Ensure cache is initialized."

              mid_price ->
                raw_price =
                  if is_buy, do: mid_price * (1 + slippage), else: mid_price * (1 - slippage)

                Format.format_price(raw_price, sz_decimals, perp: not is_spot)
            end

          price ->
            Format.format_price(price, sz_decimals, perp: not is_spot)
        end

      limit(asset, is_buy, slippage_price, formatted_size, Keyword.merge([tif: "Ioc"], opts))
    end
  end

  @doc """
  Build and place a limit order in one call.

  ## Parameters
    - `coin`: Coin symbol
    - `is_buy`: true for buy, false for sell
    - `limit_px`: Limit price
    - `sz`: Size
    - `opts`: Optional parameters (see `limit_order/5` and `place/3`)

  ## Options
    - `:private_key` - Private key for signing (falls back to config)

  ## Examples

      {:ok, result} = Order.place_limit("BTC", true, 50000, 0.1)
      {:ok, result} = Order.place_limit("ETH", false, 3500, 1.5, tif: "Ioc", private_key: "abc...")

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  def place_limit(coin, is_buy, limit_px, sz, opts \\ []) do
    case limit_order(coin, is_buy, limit_px, sz, opts) do
      {:error, _} = error -> error
      order -> place(order, opts)
    end
  end

  @doc """
  Build and place a trigger order in one call.

  ## Parameters
    - `coin`: Coin symbol
    - `is_buy`: true for buy, false for sell
    - `limit_px`: Limit price
    - `sz`: Size
    - `trigger_px`: Trigger price
    - `opts`: Optional parameters (see `trigger_order/6` and `place/3`)

  ## Options
    - `:private_key` - Private key for signing (falls back to config)

  ## Examples

      {:ok, result} = Order.place_trigger("BTC", false, 48000, 0.1, 49000, tpsl: "sl")

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  def place_trigger(coin, is_buy, limit_px, sz, trigger_px, opts \\ []) do
    case trigger_order(coin, is_buy, limit_px, sz, trigger_px, opts) do
      {:error, _} = error -> error
      order -> place(order, opts)
    end
  end

  @doc """
  Build and place a market order in one call.

  ## Parameters
    - `coin`: Coin symbol
    - `is_buy`: true for buy, false for sell
    - `sz`: Size
    - `opts`: Optional parameters (see `market_order/4` and `place/3`)

  ## Options
    - `:private_key` - Private key for signing (falls back to config)

  ## Examples

      {:ok, result} = Order.place_market("BTC", true, 0.1)
      {:ok, result} = Order.place_market("ETH", false, 1.5, slippage: 0.03)

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  def place_market(coin, is_buy, sz, opts \\ []) do
    case market_order(coin, is_buy, sz, opts) do
      {:error, _} = error -> error
      order -> place(order, opts)
    end
  end

  # Resolve coin symbol to asset index and decimals
  defp resolve_coin(coin) do
    is_spot = String.contains?(coin, "/")

    case Cache.asset_from_coin(coin) do
      nil ->
        {:error, {:coin_not_found, coin}}

      asset ->
        sz_decimals =
          if is_spot do
            Cache.spot_pair_decimals(coin)
          else
            Cache.decimals_from_coin(coin)
          end

        {:ok, asset, sz_decimals || 0, is_spot}
    end
  end

  # ===================== Types =====================

  @type limit_order :: %{
          asset: non_neg_integer(),
          is_buy: boolean(),
          limit_px: String.t(),
          sz: String.t(),
          reduce_only: boolean(),
          order_type: :limit,
          tif: String.t(),
          cloid: String.t() | nil
        }

  @type trigger_order :: %{
          asset: non_neg_integer(),
          is_buy: boolean(),
          limit_px: String.t(),
          sz: String.t(),
          reduce_only: boolean(),
          order_type: :trigger,
          trigger_px: String.t(),
          is_market: boolean(),
          tpsl: String.t(),
          cloid: String.t() | nil
        }

  @type order :: limit_order() | trigger_order()

  @type grouping :: :na | :normal_tpsl | :position_tpsl

  @type builder_info :: %{
          builder: String.t(),
          fee: non_neg_integer()
        }

  @type order_opts :: [
          vault_address: String.t(),
          builder: builder_info()
        ]

  @type order_response :: %{
          status: String.t(),
          response: %{
            type: String.t(),
            data: %{
              statuses: list()
            }
          }
        }

  # ===================== Order Builders =====================

  @doc """
  Build a limit order.

  ## Parameters
    - `asset`: Asset index
    - `is_buy`: true for buy, false for sell
    - `limit_px`: Limit price as string
    - `sz`: Size as string
    - `opts`: Optional parameters

  ## Options
    - `:reduce_only` - Only reduce position (default: false)
    - `:tif` - Time in force: "Gtc", "Ioc", "Alo" (default: "Gtc")
    - `:cloid` - Client order ID

  ## Examples

      Order.limit(0, true, "50000.0", "0.1")
      Order.limit(0, true, "50000.0", "0.1", tif: "Ioc", cloid: "my-order-1")
  """
  @spec limit(non_neg_integer(), boolean(), String.t(), String.t(), keyword()) :: limit_order()
  def limit(asset, is_buy, limit_px, sz, opts \\ []) do
    %{
      asset: asset,
      is_buy: is_buy,
      limit_px: limit_px,
      sz: sz,
      reduce_only: Keyword.get(opts, :reduce_only, false),
      order_type: :limit,
      tif: Keyword.get(opts, :tif, "Gtc"),
      cloid: Keyword.get(opts, :cloid)
    }
  end

  @doc """
  Build a trigger order (stop-loss or take-profit).

  ## Parameters
    - `asset`: Asset index
    - `is_buy`: true for buy, false for sell
    - `limit_px`: Limit price as string (use far price for market trigger)
    - `sz`: Size as string
    - `trigger_px`: Trigger price as string
    - `opts`: Optional parameters

  ## Options
    - `:reduce_only` - Only reduce position (default: false)
    - `:is_market` - Execute as market order when triggered (default: true)
    - `:tpsl` - "sl" for stop-loss, "tp" for take-profit (default: "sl")
    - `:cloid` - Client order ID

  ## Examples

      # Stop-loss at 49000
      Order.trigger(0, false, "48000.0", "0.1", "49000.0", tpsl: "sl")

      # Take-profit at 55000
      Order.trigger(0, false, "56000.0", "0.1", "55000.0", tpsl: "tp")
  """
  @spec trigger(non_neg_integer(), boolean(), String.t(), String.t(), String.t(), keyword()) ::
          trigger_order()
  def trigger(asset, is_buy, limit_px, sz, trigger_px, opts \\ []) do
    %{
      asset: asset,
      is_buy: is_buy,
      limit_px: limit_px,
      sz: sz,
      reduce_only: Keyword.get(opts, :reduce_only, false),
      order_type: :trigger,
      trigger_px: trigger_px,
      is_market: Keyword.get(opts, :is_market, true),
      tpsl: Keyword.get(opts, :tpsl, "sl"),
      cloid: Keyword.get(opts, :cloid)
    }
  end

  @doc """
  Build a market order (IOC limit order at far price).

  ## Parameters
    - `asset`: Asset index
    - `is_buy`: true for buy, false for sell
    - `sz`: Size as string
    - `opts`: Optional parameters

  ## Options
    - `:slippage_price` - Far limit price for slippage protection (auto-calculated if not provided)
    - `:slippage` - Slippage percentage (default: 0.05 = 5%)
    - `:reduce_only` - Only reduce position (default: false)
    - `:cloid` - Client order ID

  When `:slippage_price` is not provided, the coin is resolved from the asset index
  via cache reverse lookup and the mid price is used to calculate slippage.

  ## Examples

      # Automatic price lookup (resolves coin from asset index)
      Order.market(0, true, "0.1")

      # With explicit slippage price
      Order.market(0, true, "0.1", slippage_price: "100000.0")
  """
  @spec market(non_neg_integer(), boolean(), String.t(), keyword()) :: limit_order()
  def market(asset, is_buy, sz, opts \\ []) do
    slippage_price = calculate_slippage_price(opts, is_buy, asset)
    limit(asset, is_buy, slippage_price, sz, Keyword.merge([tif: "Ioc"], opts))
  end

  defp calculate_slippage_price(opts, is_buy, asset) do
    case Keyword.get(opts, :slippage_price) do
      nil ->
        coin = Cache.coin_from_asset(asset)
        slippage = Keyword.get(opts, :slippage, @default_slippage)

        if coin do
          case Cache.get_mid(coin) do
            nil ->
              raise ArgumentError,
                    "Mid price not found for #{coin}. Either provide :slippage_price or ensure cache is initialized."

            mid_price ->
              price = if is_buy, do: mid_price * (1 + slippage), else: mid_price * (1 - slippage)
              sz_decimals = Cache.sz_decimals_by_asset(asset)
              is_perp = asset < 10_000
              Format.format_price(price, sz_decimals, perp: is_perp)
          end
        else
          raise ArgumentError,
                "Could not resolve coin for asset #{asset}. Provide :slippage_price or ensure cache is initialized."
        end

      price ->
        sz_decimals = Cache.sz_decimals_by_asset(asset)
        is_perp = asset < 10_000
        Format.format_price(price, sz_decimals, perp: is_perp)
    end
  end

  # ===================== Request Functions =====================

  @doc """
  Place a single order.

  ## Parameters
    - `order`: Order built with `limit/5`, `trigger/6`, or `market/5`
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:vault_address` - Trade on behalf of a vault
    - `:builder` - Builder info for builder fee

  ## Returns
    - `{:ok, response}` - Order placement result
    - `{:error, term()}` - Error details

  ## Examples

      order = Order.limit(0, true, "50000.0", "0.1")
      {:ok, result} = Order.place(order)

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  @spec place(order(), order_opts()) :: {:ok, order_response()} | {:error, term()}
  def place(order, opts \\ []) do
    place_batch([order], :na, opts)
  end

  @doc """
  Place multiple orders in a batch.

  ## Parameters
    - `orders`: List of orders
    - `grouping`: Order grouping strategy
    - `opts`: Optional parameters

  ## Grouping Options
    - `:na` - No grouping (default)
    - `:normal_tpsl` - Group TP/SL with entry order
    - `:position_tpsl` - Attach TP/SL to existing position

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:vault_address` - Trade on behalf of a vault
    - `:builder` - Builder info for builder fee

  ## Returns
    - `{:ok, response}` - Batch order result
    - `{:error, term()}` - Error details

  ## Examples

      orders = [
        Order.limit(0, true, "50000.0", "0.1"),
        Order.limit(0, true, "49000.0", "0.1")
      ]
      {:ok, result} = Order.place_batch(orders, :na)

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  @spec place_batch([order()], grouping(), order_opts()) ::
          {:ok, order_response()} | {:error, term()}
  def place_batch(orders, grouping \\ :na, opts \\ []) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    builder = Keyword.get(opts, :builder)

    # Field order is part of the signed preimage — see Hyperliquid.Api.ActionEncoder.
    action = orders |> build_action(grouping, builder) |> ActionEncoder.canonicalize()
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    debug("place_batch called", %{
      orders_count: length(orders),
      grouping: grouping,
      vault_address: vault_address,
      nonce: nonce
    })

    with {:ok, action_json} <- Jason.encode(action),
         _ <- debug("Action encoded", %{action: action}),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after),
         _ <- debug("Action signed", %{signature: signature}),
         {:ok, response} <-
           Http.exchange_request(action, signature, nonce, vault_address, expires_after) do
      debug("Response received", %{response: response})
      {:ok, response}
    else
      {:error, reason} = error ->
        debug("Error occurred", %{error: reason})
        error
    end
  end

  # ===================== Action Building =====================

  defp build_action(orders, grouping, builder) do
    action = %{
      type: "order",
      orders: Enum.map(orders, &format_order/1),
      grouping: format_grouping(grouping)
    }

    if builder do
      Map.put(action, :builder, %{
        b: builder.builder,
        f: builder.fee
      })
    else
      action
    end
  end

  defp format_order(%{order_type: :limit} = order) do
    base = %{
      a: order.asset,
      b: order.is_buy,
      p: Utils.float_to_string(order.limit_px),
      s: Utils.float_to_string(order.sz),
      r: order.reduce_only,
      t: %{
        limit: %{
          tif: order.tif
        }
      }
    }

    maybe_add_cloid(base, order.cloid)
  end

  defp format_order(%{order_type: :trigger} = order) do
    base = %{
      a: order.asset,
      b: order.is_buy,
      p: Utils.float_to_string(order.limit_px),
      s: Utils.float_to_string(order.sz),
      r: order.reduce_only,
      t: %{
        trigger: %{
          isMarket: order.is_market,
          triggerPx: Utils.float_to_string(order.trigger_px),
          tpsl: order.tpsl
        }
      }
    }

    maybe_add_cloid(base, order.cloid)
  end

  defp maybe_add_cloid(order, nil), do: order
  defp maybe_add_cloid(order, cloid), do: Map.put(order, :c, cloid)

  defp format_grouping(:na), do: "na"
  defp format_grouping(:normal_tpsl), do: "normalTpsl"
  defp format_grouping(:position_tpsl), do: "positionTpsl"

  # ===================== Signing =====================

  defp sign_action(private_key, action_json, nonce, vault_address, expires_after) do
    is_mainnet = Config.mainnet?()

    case Signer.sign_exchange_action_ex(
           private_key,
           action_json,
           nonce,
           is_mainnet,
           vault_address,
           expires_after
         ) do
      %{"r" => r, "s" => s, "v" => v} ->
        {:ok, %{r: r, s: s, v: v}}

      error ->
        {:error, {:signing_error, error}}
    end
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end

  # ===================== Debug Logging =====================

  defp debug(message, data) do
    if Config.debug?() do
      Logger.debug("[Order] #{message}", data: data)
    end

    :ok
  end
end
