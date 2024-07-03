defmodule Hyperliquid.Config do
  @moduledoc """
  Configuration module for Hyperliquid application.
  """

  @doc """
  Returns the base URL of the API.
  """
  def api_base do
    Application.get_env(:hyperliquid, :http_url, "https://api.hyperliquid.xyz")
  end

  @doc """
  Returns the ws URL of the API.
  """
  def ws_url do
    Application.get_env(:hyperliquid, :ws_url, "wss://api.hyperliquid.xyz/ws")
  end

  @doc """
  Returns whether the application is running on mainnet.
  """
  def mainnet? do
    Application.get_env(:hyperliquid, :is_mainnet, true)
  end

  @doc """
  Returns the private key.
  """
  def secret do
    Application.get_env(:hyperliquid, :private_key, nil)
  end

  @doc """
  Returns the bridge contract address, used for deposits.
  """
  def bridge_contract do
    Application.get_env(:hyperliquid, :hl_bridge_contract, "0x2df1c51e09aecf9cacb7bc98cb1742757f163df7")
  end
end
