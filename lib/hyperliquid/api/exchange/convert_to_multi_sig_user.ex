defmodule Hyperliquid.Api.Exchange.ConvertToMultiSigUser do
  @moduledoc """
  Convert a single-signature account to a multi-signature account, or back.

  `convertToMultiSigUser` is a **user-signed** (EIP-712) action, not an L1
  msgpack action. It is signed under
  `HyperliquidTransaction:ConvertToMultiSigUser` with the fields
  `hyperliquidChain`, `signers`, `nonce`, matching `@nktkas/hyperliquid` and
  `hyperliquid-python-sdk` (`CONVERT_TO_MULTI_SIG_USER_SIGN_TYPES`). Until
  the 2026-09 API sync this module built and hashed an L1 action with the
  signers *inlined*
  (`{type, authorizedUsers, threshold}`); the wire format is a single `signers`
  **string** holding the JSON, and the signature scheme was wrong too.

  `signers` is signed as an opaque string, so the exact JSON text matters. This
  module renders `authorizedUsers` (sorted, lowercased) before `threshold` with
  no whitespace — the same text `JSON.stringify` produces in nktkas.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/hypercore/multi-sig
  """

  alias Hyperliquid.Api.Exchange.{KeyUtils, UserSigned}
  alias Hyperliquid.Config
  alias Hyperliquid.Transport.Http
  alias Hyperliquid.Utils

  @primary_type "HyperliquidTransaction:ConvertToMultiSigUser"
  @fields [{"signers", "string"}, {"nonce", "uint64"}]

  @doc """
  Convert to (or from) a multi-sig account.

  ## Parameters
    - `signers`: one of
        * `%{authorized_users: [addr], threshold: n}` (or the camelCase
          `%{"authorizedUsers" => [...], "threshold" => n}`) to convert to
          multi-sig;
        * `nil` to revert to single-sig;
        * a pre-rendered JSON string, used verbatim.
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:expected_address` - When provided, validates the private key derives to this address

  ## Returns
    - `{:ok, response}` - Result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} =
        ConvertToMultiSigUser.request(%{authorized_users: ["0x...", "0x..."], threshold: 2})

      # back to single-sig
      {:ok, result} = ConvertToMultiSigUser.request(nil)
  """
  def request(signers, opts \\ []) do
    private_key = KeyUtils.resolve_and_validate!(opts)
    signers = encode_signers(signers)
    nonce = Utils.generate_nonce()
    is_mainnet = Config.mainnet?()

    with {:ok, signature} <- sign(private_key, signers, nonce, is_mainnet) do
      Http.user_signed_request(
        build_action(signers, nonce, is_mainnet),
        signature,
        nonce,
        opts
      )
    end
  end

  @doc """
  Renders the `signers` field to the exact JSON string that gets signed.

  `nil` becomes `"null"`; a string is passed through untouched.
  """
  def encode_signers(nil), do: "null"
  def encode_signers(signers) when is_binary(signers), do: signers

  def encode_signers(signers) when is_map(signers) do
    users =
      signers
      |> fetch(:authorized_users, "authorizedUsers")
      |> Enum.map(&String.downcase/1)
      |> Enum.sort()

    threshold = fetch(signers, :threshold, "threshold")

    Jason.encode!(Jason.OrderedObject.new([{:authorizedUsers, users}, {:threshold, threshold}]))
  end

  defp fetch(map, atom_key, string_key) do
    case Map.fetch(map, atom_key) do
      {:ok, value} -> value
      :error -> Map.fetch!(map, string_key)
    end
  end

  @doc """
  The wire action, in the canonical field order
  (`type`, `signatureChainId`, `hyperliquidChain`, `signers`, `nonce`).
  """
  def build_action(signers, nonce, is_mainnet \\ nil) when is_binary(signers) do
    Jason.OrderedObject.new([
      {:type, "convertToMultiSigUser"},
      {:signatureChainId, UserSigned.signature_chain_id()},
      {:hyperliquidChain, UserSigned.hyperliquid_chain(is_mainnet)},
      {:signers, signers},
      {:nonce, nonce}
    ])
  end

  @doc false
  def sign(private_key, signers, nonce, is_mainnet \\ nil) when is_binary(signers) do
    UserSigned.sign(
      private_key,
      @primary_type,
      @fields,
      [{"signers", signers}, {"nonce", nonce}],
      is_mainnet
    )
  end
end
