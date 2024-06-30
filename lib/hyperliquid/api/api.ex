defmodule Hyperliquid.Api do

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
