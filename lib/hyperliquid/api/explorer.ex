defmodule Hyperliquid.Api.Explorer do
  @moduledoc """
  Module for interacting with the Hyperliquid Explorer API endpoints.

  This module provides functions to query various details from the Hyperliquid blockchain,
  including block details, transaction details, and user details.

  It uses the `Hyperliquid.Api` macro to set up the basic API interaction functionality.

  ## Usage

  You can use this module to make queries to the Explorer API:

      Hyperliquid.Api.Explorer.block_details(12345)
      Hyperliquid.Api.Explorer.tx_details("0x1234...")
      Hyperliquid.Api.Explorer.user_details("0xabcd...")

  ## Functions

  - `block_details/1` - Retrieve details for a specific block
  - `tx_details/1` - Retrieve details for a specific transaction
  - `user_details/1` - Retrieve details for a specific user address

  All functions return a tuple `{:ok, result}` on success, or `{:error, details}` on failure.
  """

  use Hyperliquid.Api, context: "explorer"

  @doc """
  Retrieves details for a specific block.

  ## Parameters

  - `block`: The block height to query

  ## Example

      iex> Hyperliquid.Api.Explorer.block_details(12345)
      {:ok, %{
        "blockDetails" => %{
          "blockTime" => 1677437426106,
          "hash" => "0x0b2c0480a44085b1b3206fafd19634e8ed435b02d0c1962de0616838fe13f817",
          "height" => 12345,
          "numTxs" => 1,
          "proposer" => "3BFD93BEAF77A51598FEA7BA084DDD2E798EC37A",
          "txs" => [
            %{
              "action" => %{"cancels" => [%{"a" => 3, "o" => 23482}], "type" => "cancel"},
              "block" => 12345,
              "error" => nil,
              "hash" => "0x5e2593db2fe88b32270f02303900005e650d7594bf1154b1b3b7b30e0137426f",
              "time" => 1677437426106,
              "user" => "0xb7b6f3cea3f66bf525f5d8f965f6dbf6d9b017b2"
            }
          ]
        },
        "type" => "blockDetails"
      }}
  """
  def block_details(block) do
    post(%{type: "blockDetails", height: block})
  end

  @doc """
  Retrieves details for a specific transaction.

  ## Parameters

  - `hash`: The transaction hash to query

  ## Example

      iex> Hyperliquid.Api.Explorer.tx_details("0xf94afe652b34cc43d688040cb9571100001ca826f770b3adb1358e2c82d59be8")
      {:ok, %{
        "tx" => %{
          "action" => %{
            "cancels" => [%{"asset" => 75, "cloid" => "0x00000000000003800076757960710291"}],
            "type" => "cancelByCloid"
          },
          "block" => 213473041,
          "error" => nil,
          "hash" => "0xf94afe652b34cc43d688040cb9571100001ca826f770b3adb1358e2c82d59be8",
          "time" => 1719979999193,
          "user" => "0xaf9f722a676230cc44045efe26fe9a85801ca4fa"
        },
        "type" => "txDetails"
      }}
  """
  def tx_details(hash) do
    post(%{type: "txDetails", hash: hash})
  end

  @doc """
  Retrieves details for a specific user address.

  ## Parameters

  - `user_address`: The user address to query

  ## Example

      iex> Hyperliquid.Api.Explorer.user_details("0xabcd...")
      {:ok, %{
        "txs" => [
          %{
            "action" => %{"cancels" => [%{"a" => 136, "o" => 26403012371}], "type" => "cancel"},
            "block" => 195937903,
            "error" => nil,
            "hash" => "0x62307db3f7e254b668fe040badc66f017c00e1fe11758901a25f7a562f7c019b",
            "time" => 1718631244781,
            "user" => "0x25c32751bc8de15e282919ba3946def63c044dea"
          }
        ],
        "type" => "userDetails"
      }}
  """
  def user_details(user_address) do
    post(%{type: "userDetails", user: user_address})
  end
end
