defmodule Hyperliquid.Api.Exchange do
  use Hyperliquid.Api, context: "exchange"

  def place_order(order), do: place_order(order, "na", nil)
  def place_order(order, grouping \\ "na", vault_address \\ nil)

  def place_order([_|_] = orders, grouping, vault_address) do
    post_action(%{type: "order", grouping: grouping, orders: orders}, vault_address)
  end

  def place_order(order, grouping, vault_address) do
    post_action(%{type: "order", grouping: grouping, orders: [order]}, vault_address)
  end

  def cancel_orders([_|_] = cancels, vault_address \\ nil) do
    post_action(%{type: "cancel", cancels: cancels}, vault_address)
  end

  def cancel_order(asset, oid, vault_address \\ nil) do
    post_action(%{type: "cancel", cancels: [%{a: asset, o: oid}]}, vault_address)
  end

  def cancel_order_by_cloid(asset, cloid, vault_address \\ nil) do
    post_action(%{type: "cancelByCloid", cancels: [%{asset: asset, cloid: cloid}]}, vault_address)
  end

  def cancel_orders_by_cloid([_|_] = cancels, vault_address \\ nil) do
    post_action(%{type: "cancelByCloid", cancels: cancels}, vault_address)
  end

  def modify_order(oid, order, vault_address \\ nil) do
    post_action(%{type: "modify", oid: oid, order: order}, vault_address)
  end

  def modify_multiple_orders(modifies, vault_address \\ nil) do
    post_action(%{type: "batchModify", modifies: modifies}, vault_address)
  end

  #TESTED
  def update_leverage(asset, is_cross, leverage) do
    post_action(%{
      type: "updateLeverage",
      asset: asset,
      isCross: is_cross,
      leverage: leverage
    })
  end

  #TESTED
  def update_isolated_margin(asset, is_buy, ntli) do
    post_action(%{
      type: "updateIsolatedMargin",
      asset: asset,
      isBuy: is_buy,
      ntli: ntli
    })
  end

  # TESTED
  def spot_perp_transfer(amount, to_perp) do
    post_action(%{
      type: "spotUser",
      classTransfer: %{
        usdc: amount,
        toPerp: to_perp
      }
    })
  end

  # TESTED
  def vault_transfer(vault_address, is_deposit, amount_usd) do
    post_action(%{
      type: "vaultTransfer",
      vaultAddress: vault_address,
      isDeposit: is_deposit,
      usd: amount_usd
    })
    # positive usd = transfer, negative = withdraw
  end

  # TESTED
  def create_sub_account(name) do
    post_action(%{
      type: "createSubAccount",
      name: name
    })
  end

  # TESTED
  def sub_account_transfer(user, is_deposit, amount_usd) do
    post_action(%{
      type: "subAccountTransfer",
      subAccountUser: user,
      isDeposit: is_deposit,
      usd: amount_usd # MUST BE INT VALUE - 1_000_000 = $1
    })
  end

  # TESTED
  def sub_account_spot_transfer(user, is_deposit, token, amount) do
    post_action(%{
      type: "subAccountSpotTransfer",
      subAccountUser: user,
      isDeposit: is_deposit,
      token: token,
      amount: amount
    })
  end

  ####### non l1 actions with different signer ##########

  # TESTED
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

  # TESTED
  def spot_send(destination, token, amount, time) do
    #TODO: programatically get tokenname and address
    post_action(%{
      type: "spotSend",
      hyperliquidChain: if(mainnet?(), do: "Mainnet", else: "Testnet"),
      signatureChainId: if(mainnet?(), do: to_hex(42_161), else: to_hex(421_614)),
      destination: Ethers.Utils.to_checksum_address(destination),
      token: token, #tokenName:tokenId, e.g. "PURR:0xc4bf3f870c0e9465323c0b6ed28096c2"
      amount: amount,
      time: time
    }, time)
  end

  # TESTED
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
