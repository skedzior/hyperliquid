defmodule Hyperliquid.Api.Exchange.SendAsset do
  @moduledoc """
  Transfer tokens between different perp DEXs, spot balance, users, and/or sub-accounts.

  `sendAsset` is a **user-signed** (EIP-712) action, signed under
  `HyperliquidTransaction:SendAsset` with the fields `hyperliquidChain`,
  `destination`, `sourceDex`, `destinationDex`, `token`, `amount`,
  `fromSubAccount`, `nonce`, matching `@nktkas/hyperliquid` (`SendAssetTypes`)
  and `hyperliquid-python-sdk` (`SEND_ASSET_SIGN_TYPES`).

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint#send-asset
  """

  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http
  alias Hyperliquid.Utils

  @primary_type "HyperliquidTransaction:SendAsset"
  @fields [
    {"destination", "string"},
    {"sourceDex", "string"},
    {"destinationDex", "string"},
    {"token", "string"},
    {"amount", "string"},
    {"fromSubAccount", "string"},
    {"nonce", "uint64"}
  ]

  @doc """
  Transfer tokens between different perp DEXs, spot balance, users, and/or sub-accounts.

  ## Parameters
    - `destination`: Destination address
    - `source_dex`: Source DEX ("" for default USDC perp DEX, "spot" for spot)
    - `destination_dex`: Destination DEX ("" for default USDC perp DEX, "spot" for spot)
    - `token`: Token identifier (e.g., "USDC:0xeb62eee3685fc4c43992febcd9e75443")
    - `amount`: Amount to send as string (not in wei)
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:expected_address` - When provided, validates the private key derives to this address
    - `:from_sub_account` - Source sub-account address ("" for main account, default: "")

  ## Returns
    - `{:ok, response}` - Transfer result
    - `{:error, term()}` - Error details

  ## Examples

      # Transfer from perp to spot
      {:ok, result} = SendAsset.request(
        "0x...",
        "",
        "spot",
        "USDC:0xeb62eee3685fc4c43992febcd9e75443",
        "100.0"
      )

  ## Breaking Change (v0.2.0)
  `private_key` was previously the first positional argument. It is now
  an option in the opts keyword list (`:private_key`).
  """
  def request(
        destination,
        source_dex,
        destination_dex,
        token,
        amount,
        opts \\ []
      ) do
    private_key = KeyUtils.resolve_and_validate!(opts)
    time = Utils.generate_nonce()
    is_mainnet = Config.mainnet?()
    from_sub_account = Keyword.get(opts, :from_sub_account, "")

    with {:ok, signature} <-
           sign(
             private_key,
             destination,
             source_dex,
             destination_dex,
             token,
             amount,
             from_sub_account,
             time,
             is_mainnet
           ) do
      action =
        build_action(
          destination,
          source_dex,
          destination_dex,
          token,
          amount,
          from_sub_account,
          time,
          is_mainnet
        )

      Http.user_signed_request(action, signature, time, opts)
    end
  end

  @doc """
  The wire action, in the canonical field order
  (`type`, `signatureChainId`, `hyperliquidChain`, then the signed fields).
  """
  def build_action(
        destination,
        source_dex,
        destination_dex,
        token,
        amount,
        from_sub_account,
        nonce,
        is_mainnet \\ nil
      ) do
    Jason.OrderedObject.new([
      {:type, "sendAsset"},
      {:signatureChainId, UserSigned.signature_chain_id()},
      {:hyperliquidChain, UserSigned.hyperliquid_chain(is_mainnet)},
      {:destination, destination},
      {:sourceDex, source_dex},
      {:destinationDex, destination_dex},
      {:token, token},
      {:amount, amount},
      {:fromSubAccount, from_sub_account},
      {:nonce, nonce}
    ])
  end

  @doc false
  def sign(
        private_key,
        destination,
        source_dex,
        destination_dex,
        token,
        amount,
        from_sub_account,
        nonce,
        is_mainnet \\ nil
      ) do
    UserSigned.sign(
      private_key,
      @primary_type,
      @fields,
      [
        {"destination", destination},
        {"sourceDex", source_dex},
        {"destinationDex", destination_dex},
        {"token", token},
        {"amount", amount},
        {"fromSubAccount", from_sub_account},
        {"nonce", nonce}
      ],
      is_mainnet
    )
  end
end
