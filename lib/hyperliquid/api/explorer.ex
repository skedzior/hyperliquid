defmodule Hyperliquid.Api.Explorer do
  use Hyperliquid.Api, context: "explorer"

  def block_details(block) do
    post(%{type: "blockDetails", height: block})
  end

  def tx_details(hash) do
    post(%{type: "txDetails", hash: hash})
  end

  def user_details(user_address) do
    post(%{type: "userDetails", user: user_address})
  end
end
