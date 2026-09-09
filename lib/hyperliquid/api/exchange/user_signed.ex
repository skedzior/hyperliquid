defmodule Hyperliquid.Api.Exchange.UserSigned do
  @moduledoc """
  Shared EIP-712 signing for user-signed exchange actions.

  User-signed actions (withdrawals, transfers, agent approvals) are signed over
  typed data rather than over the msgpack of the action, so field order does not
  affect the signature — but the EIP-712 domain does.

  The domain's `chainId` and the action's `signatureChainId` must always agree:
  the exchange rebuilds the domain from `signatureChainId` to recover the signer,
  so if they drift the API recovers the wrong address and rejects the action.
  Both come from `Hyperliquid.Config.signature_chain_id/0`, which is what keeps
  them in step.
  """

  alias Hyperliquid.{Config, Signer}

  @verifying_contract "0x0000000000000000000000000000000000000000"

  @doc """
  The EIP-712 domain used for every user-signed action.
  """
  @spec domain() :: map()
  def domain do
    %{
      name: "HyperliquidSignTransaction",
      version: "1",
      chainId: Config.signature_chain_id(),
      verifyingContract: @verifying_contract
    }
  end

  @doc """
  `"Mainnet"` or `"Testnet"`, the field that actually selects the network.

  Takes the network from `Hyperliquid.Config.mainnet?/0` unless an explicit
  boolean is given, so a caller that has already read the config can pass it
  through rather than reading it twice.
  """
  @spec hyperliquid_chain(boolean() | nil) :: String.t()
  def hyperliquid_chain(is_mainnet \\ nil)
  def hyperliquid_chain(nil), do: hyperliquid_chain(Config.mainnet?())
  def hyperliquid_chain(true), do: "Mainnet"
  def hyperliquid_chain(false), do: "Testnet"

  @doc """
  The `signatureChainId` field to send in the action body.
  """
  @spec signature_chain_id() :: String.t()
  def signature_chain_id, do: Config.signature_chain_id_hex()

  @doc """
  Sign a user-signed action's typed data.

  ## Parameters
    - `private_key`: Private key for signing
    - `primary_type`: EIP-712 primary type, e.g. `"HyperliquidTransaction:UsdSend"`
    - `types`: List of `%{name: ..., type: ...}` field descriptors, in order
    - `message`: The message to sign

  ## Returns
    - `{:ok, %{r: ..., s: ..., v: ...}}`
    - `{:error, {:signing_error, term()}}`
  """
  @spec sign(String.t(), String.t(), [map()], map()) ::
          {:ok, map()} | {:error, term()}
  def sign(private_key, primary_type, types, message) do
    with {:ok, domain_json} <- Jason.encode(domain()),
         {:ok, types_json} <- Jason.encode(%{primary_type => types}),
         {:ok, message_json} <- Jason.encode(message) do
      case Signer.sign_typed_data(
             private_key,
             domain_json,
             types_json,
             message_json,
             primary_type
           ) do
        %{"r" => r, "s" => s, "v" => v} -> {:ok, %{r: r, s: s, v: v}}
        error -> {:error, {:signing_error, error}}
      end
    end
  end

  @doc """
  Sign a user-signed action from its field list and values.

  A convenience wrapper over `sign/4` for the common case: every Hyperliquid
  user-signed struct starts with `hyperliquidChain`, so it is prepended to both
  the type and the message here and cannot drift between them.

    * `fields` — the signed struct's fields **after** `hyperliquidChain`, in
      EIP-712 declaration order, as `[{name, solidity_type}]`
    * `message` — the matching values as a map or keyword list, without
      `hyperliquidChain`
    * `is_mainnet` — `nil` to read `Hyperliquid.Config.mainnet?/0`
  """
  @spec sign(String.t(), String.t(), [{String.t(), String.t()}], Enumerable.t(), boolean() | nil) ::
          {:ok, map()} | {:error, term()}
  def sign(private_key, primary_type, fields, message, is_mainnet) do
    types =
      [%{name: "hyperliquidChain", type: "string"}] ++
        Enum.map(fields, fn {name, type} -> %{name: name, type: type} end)

    message =
      message
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Map.new()
      |> Map.put("hyperliquidChain", hyperliquid_chain(is_mainnet))

    sign(private_key, primary_type, types, message)
  end
end
