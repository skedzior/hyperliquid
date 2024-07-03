defmodule Hyperliquid.Api do
  @moduledoc """
  A base API macro for interacting with the Hyperliquid API.

  This module provides a macro that sets up common functionality for API interactions,
  including signing requests, handling different types of actions, and processing responses.

  When used, it imports necessary modules, sets up aliases, and defines several helper functions
  for making API calls.

  ## Usage

  Use this module in other API-specific modules like this:

      use Hyperliquid.Api, context: "evm"

  ## Configuration

  This module relies on the following application environment variables:

  - `:http_url` - The base URL for API requests
  - `:is_mainnet` - Boolean indicating whether to use mainnet or testnet
  - `:private_key` - The private key used for signing requests

  """
  defmacro __using__(opts) do
    quote do
      import Hyperliquid.{Api, Utils}
      alias Hyperliquid.Signer

      @context unquote(Keyword.get(opts, :context, ""))

      @api_base Application.get_env(:hyperliquid, :http_url)
      @is_mainnet Application.get_env(:hyperliquid, :is_mainnet)
      @secret Application.get_env(:hyperliquid, :private_key)

      @headers [{"Content-Type", "application/json"}]

      def mainnet?, do: @is_mainnet
      def endpoint, do: "#{@api_base}/#{@context}"

      def post_action(action), do: post_action(action, nil, get_timestamp(), @secret)
      def post_action(action, vault_address), do: post_action(action, vault_address, get_timestamp(), @secret)
      def post_action(action, vault_address, nonce), do: post_action(action, vault_address, nonce, @secret)

      def post_action(%{type: "usdSend"} = action, nil, nonce, secret) do
        signature = Signer.sign_usd_transfer_action(action, @is_mainnet, secret)
        payload = %{
          action: action,
          nonce: nonce,
          signature: signature,
          vaultAddress: nil
        }

        post_signed(payload)
      end

      def post_action(%{type: "spotSend"} = action, nil, nonce, secret) do
        signature = Signer.sign_spot_transfer_action(action, @is_mainnet, secret)
        payload = %{
          action: action,
          nonce: nonce,
          signature: signature,
          vaultAddress: nil
        }

        post_signed(payload)
      end

      def post_action(%{type: "withdraw3"} = action, nil, nonce, secret) do
        signature = Signer.sign_withdraw_from_bridge_action(action, @is_mainnet, secret)
        payload = %{
          action: action,
          nonce: nonce,
          signature: signature,
          vaultAddress: nil
        }

        post_signed(payload)
      end

      def post_action(action, vault_address, nonce, secret) do
        signature = Signer.sign_l1_action(action, vault_address, nonce, @is_mainnet, secret)
        payload = %{
          action: action,
          nonce: nonce,
          signature: signature,
          vaultAddress: vault_address
        }

        post_signed(payload)
      end

      def post(payload) do
        HTTPoison.post(endpoint(), Jason.encode!(payload), @headers)
        |> handle_response()
      end

      def post_signed(payload) do
        HTTPoison.post(endpoint(), Jason.encode!(payload), @headers)
        |> handle_response()
      end
    end
  end

  def handle_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    {:ok, Jason.decode!(body)}
  end

  def handle_response({:ok, %HTTPoison.Response{status_code: status_code, body: body}}) do
    {:error, %{status_code: status_code, message: body}}
  end

  def handle_response({:error, %HTTPoison.Error{reason: reason}}) do
    {:error, %{reason: reason}}
  end
end
