defmodule Hyperliquid.Api.Exchange do
  @moduledoc """
  Module for interacting with the Hyperliquid Exchange API endpoints.

  This module provides functions to perform various operations on the Hyperliquid exchange,
  including placing and canceling orders, modifying orders, updating leverage, transferring
  funds, and managing sub-accounts.

  It uses the `Hyperliquid.Api` macro to set up the basic API interaction functionality.

  ## Functions

  ### Order Management
  - `place_order/1`, `place_order/2`, `place_order/3` - Place one or multiple orders
  - `cancel_orders/1`, `cancel_orders/2` - Cancel multiple orders
  - `cancel_order/2`, `cancel_order/3` - Cancel a single order
  - `cancel_order_by_cloid/2`, `cancel_order_by_cloid/3` - Cancel an order by client order ID
  - `cancel_orders_by_cloid/1`, `cancel_orders_by_cloid/2` - Cancel multiple orders by client order IDs
  - `modify_order/2`, `modify_order/3` - Modify an existing order
  - `modify_multiple_orders/1`, `modify_multiple_orders/2` - Modify multiple orders

  ### Account Management
  - `update_leverage/3` - Update leverage for an asset
  - `update_isolated_margin/3` - Update isolated margin for an asset
  - `spot_perp_transfer/2` - Transfer between spot and perpetual accounts
  - `vault_transfer/3` - Transfer to/from a vault
  - `create_sub_account/1` - Create a sub-account
  - `sub_account_transfer/3` - Transfer funds to/from a sub-account
  - `sub_account_spot_transfer/4` - Transfer spot tokens to/from a sub-account

  ### Withdrawal and Transfers
  - `usd_send/3` - Send USD to another address
  - `spot_send/4` - Send spot tokens to another address
  - `withdraw_from_bridge/3` - Withdraw funds from the bridge

  All functions return a tuple `{:ok, result}` on success, or `{:error, details}` on failure.
  """
  use Hyperliquid.Api, context: "exchange"

  @doc """
  Places one or multiple orders.

  ## Parameters

  - `order`: A single order or a list of orders
  - `grouping`: Order grouping (default: "na")
  - `vault_address`: Optional vault address

  ## Examples

      iex> Hyperliquid.Api.Exchange.place_order(order)
      {:ok,
        %{
          "response" => %{
            "data" => %{
              "statuses" => [
                %{"filled" => %{"avgPx" => "115.17", "oid" => 18422439200, "totalSz" => "1.0"}}
              ]
            },
            "type" => "order"
          },
          "status" => "ok"
        }}
  """
  def place_order(order), do: place_order(order, "na", nil)
  def place_order(order, grouping \\ "na", vault_address \\ nil)

  def place_order([_|_] = orders, grouping, vault_address) do
    post_action(%{type: "order", grouping: grouping, orders: orders}, vault_address)
  end

  def place_order(order, grouping, vault_address) do
    post_action(%{type: "order", grouping: grouping, orders: [order]}, vault_address)
  end

  @doc """
  Cancels multiple orders.

  ## Parameters

  - `cancels`: List of orders to cancel
  - `vault_address`: Optional vault address

  ## Example

      iex> Hyperliquid.Api.Exchange.cancel_orders([%{a: 5, o: 123}, %{a: 5, o: 456}])
      {:ok, %{...}}
  """
  def cancel_orders([_|_] = cancels, vault_address \\ nil) do
    post_action(%{type: "cancel", cancels: cancels}, vault_address)
  end

  @doc """
  Cancels a single order.

  ## Parameters

  - `asset`: Integer representing the asset's index in the coin list
  - `oid`: The order ID to cancel
  - `vault_address`: Optional vault address

  ## Example

      iex> Hyperliquid.Api.Exchange.cancel_order(5, 123)
      {:ok, %{...}}
  """
  def cancel_order(asset, oid, vault_address \\ nil) do
    post_action(%{type: "cancel", cancels: [%{a: asset, o: oid}]}, vault_address)
  end

  @doc """
  Cancels order by cloid.

  ## Parameters

  - `asset`: Integer representing the asset's index in the coin list
  - `cloid`: The cloid to cancel
  - `vault_address`: Optional vault address

  ## Example

      iex> Hyperliquid.Api.Exchange.cancel_order_by_cloid(5, "0x123")
      {:ok, %{...}}
  """
  def cancel_order_by_cloid(asset, cloid, vault_address \\ nil) do
    post_action(%{type: "cancelByCloid", cancels: [%{asset: asset, cloid: cloid}]}, vault_address)
  end

  def cancel_orders_by_cloid([_|_] = cancels, vault_address \\ nil) do
    post_action(%{type: "cancelByCloid", cancels: cancels}, vault_address)
  end

  @doc """
  Modifies an existing order.

  ## Parameters

  - `oid`: The order ID to modify
  - `order`: A map containing the new order details
  - `vault_address`: Optional vault address

  ## Example

      iex> Hyperliquid.Api.Exchange.modify_order(123, order)
      {:ok, %{...}}
  """
  def modify_order(oid, order, vault_address \\ nil) do
    post_action(%{type: "modify", oid: oid, order: order}, vault_address)
  end

  def modify_multiple_orders(modifies, vault_address \\ nil) do
    post_action(%{type: "batchModify", modifies: modifies}, vault_address)
  end

  @doc """
  Updates the leverage for a specific asset.

  ## Parameters

  - `asset`: Integer representing the asset's index in the coin list
  - `is_cross`: Boolean indicating whether to use cross margin
  - `leverage`: The new leverage value

  ## Example

      iex> Hyperliquid.Api.Exchange.update_leverage(1, true, 10)
      {:ok, %{...}}
  """
  def update_leverage(asset, is_cross, leverage) do
    post_action(%{
      type: "updateLeverage",
      asset: asset,
      isCross: is_cross,
      leverage: leverage
    })
  end

  @doc """
  Updates the isolated margin for a specific asset.

  ## Parameters

  - `asset`: Integer representing the asset's index in the coin list
  - `is_buy`: Boolean indicating whether it's a buy position
  - `ntli`: The new notional total liability increase

  ## Example

      iex> Hyperliquid.Api.Exchange.update_isolated_margin(1, true, 1000)
      {:ok, %{...}}
  """
  def update_isolated_margin(asset, is_buy, ntli) do
    post_action(%{
      type: "updateIsolatedMargin",
      asset: asset,
      isBuy: is_buy,
      ntli: ntli
    })
  end

  @doc """
  Transfers funds between spot and perpetual accounts.

  ## Parameters

  - `amount`: The amount to transfer (in USDC)
  - `to_perp`: Boolean indicating the direction of transfer (true for spot to perp, false for perp to spot)

  ## Example

      iex> Hyperliquid.Api.Exchange.spot_perp_transfer(1000, true)
      {:ok, %{...}}
  """
  def spot_perp_transfer(amount, to_perp) do
    post_action(%{
      type: "spotUser",
      classTransfer: %{
        usdc: amount,
        toPerp: to_perp
      }
    })
  end

  @doc """
  Transfers funds to or from a vault.

  ## Parameters

  - `vault_address`: The address of the vault
  - `is_deposit`: Boolean indicating whether it's a deposit (true) or withdrawal (false)
  - `amount_usd`: The amount to transfer in USD (positive for transfer, negative for withdraw)

  ## Example

      iex> Hyperliquid.Api.Exchange.vault_transfer("0x1234...", true, 1000)
      {:ok, %{...}}
  """
  def vault_transfer(vault_address, is_deposit, amount_usd) do
    post_action(%{
      type: "vaultTransfer",
      vaultAddress: vault_address,
      isDeposit: is_deposit,
      usd: amount_usd
    })
  end

  @doc """
  Creates a new sub-account.

  ## Parameters

  - `name`: The name for the new sub-account

  ## Example

      iex> Hyperliquid.Api.Exchange.create_sub_account("trading_bot_1")
      {:ok, %{...}}
  """
  def create_sub_account(name) do
    post_action(%{
      type: "createSubAccount",
      name: name
    })
  end

  @doc """
  Transfers funds to or from a sub-account.

  ## Parameters

  - `user`: The address or identifier of the sub-account
  - `is_deposit`: Boolean indicating whether it's a deposit (true) or withdrawal (false)
  - `amount_usd`: The amount to transfer in USD cents (e.g., 1_000_000 = $1)

  ## Example

      iex> Hyperliquid.Api.Exchange.sub_account_transfer("0x5678...", true, 1_000_000)
      {:ok, %{...}}
  """
  def sub_account_transfer(user, is_deposit, amount_usd) do
    post_action(%{
      type: "subAccountTransfer",
      subAccountUser: user,
      isDeposit: is_deposit,
      usd: amount_usd # MUST BE INT VALUE - 1_000_000 = $1
    })
  end

  @doc """
  Transfers spot tokens to or from a sub-account.

  ## Parameters

  - `user`: The address or identifier of the sub-account
  - `is_deposit`: Boolean indicating whether it's a deposit (true) or withdrawal (false)
  - `token`: The token to transfer (e.g., "BTC", "ETH")
  - `amount`: The amount of the token to transfer

  ## Example

      iex> Hyperliquid.Api.Exchange.sub_account_spot_transfer("0x9876...", true, "BTC", 0.1)
      {:ok, %{...}}
  """
  def sub_account_spot_transfer(user, is_deposit, token, amount) do
    post_action(%{
      type: "subAccountSpotTransfer",
      subAccountUser: user,
      isDeposit: is_deposit,
      token: token,
      amount: amount
    })
  end

  def set_referrer(code) do
    post_action(%{
      type: "setReferrer",
      code: code
    })
  end

  ####### non l1 actions with different signer ##########

  def usd_send(destination, amount, time) do
    %{
      type: "usdSend",
      destination: Ethers.Utils.to_checksum_address(destination),
      amount: amount,
      time: time
    }
    |> set_action_chains(mainnet?())
    |> post_action(time)
  end

  def spot_send(destination, token, amount, time) do
    # use Cache.get_token_key(name) to get the proper token key
    # tokenName:tokenId, e.g. "PURR:0xc1fb593aeffbeb02f85e0308e9956a90"
    post_action(%{
      type: "spotSend",
      hyperliquidChain: if(mainnet?(), do: "Mainnet", else: "Testnet"),
      signatureChainId: if(mainnet?(), do: to_hex(42_161), else: to_hex(421_614)),
      destination: Ethers.Utils.to_checksum_address(destination),
      token: token,
      amount: amount,
      time: time
    }, nil, time)
  end

  @doc """
  Withdraws funds from the bridge.

  ## Parameters

  - `destination`: The destination address
  - `amount`: The amount to withdraw
  - `time`: The timestamp for the withdrawal

  ## Returns

  `{:ok, result}` on success, where `result` contains the response from the API.
  `{:error, details}` on failure.

  ## Example

      iex> Hyperliquid.Api.Exchange.withdraw_from_bridge("0x1234...", 1000000, 1625097600)
      {:ok, %{...}}
  """
  def withdraw_from_bridge(destination, amount, time) do
    post_action(%{
      type: "withdraw3",
      hyperliquidChain: if(mainnet?(), do: "Mainnet", else: "Testnet"),
      signatureChainId: if(mainnet?(), do: to_hex(42_161), else: to_hex(421_614)),
      amount: amount,
      time: time,
      destination: Ethers.Utils.to_checksum_address(destination)
    }, time)
  end

  defp set_action_chains(action, true) do
    Map.merge(action, %{
      hyperliquidChain: "Mainnet",
      signatureChainId: to_hex(42_161)
    })
  end

  defp set_action_chains(action, false) do
    Map.merge(action, %{
      hyperliquidChain: "Testnet",
      signatureChainId: to_hex(421_614)
    })
  end
end
