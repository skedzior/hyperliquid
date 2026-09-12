defmodule Hyperliquid.Api.MultiSig do
  @moduledoc """
  Build, sign and send Hyperliquid `multiSig` actions.

  A multi-sig action wraps an ordinary exchange action so that it is executed on
  behalf of a *multi-sig user* (a converted account, see
  `Hyperliquid.Api.Exchange.ConvertToMultiSigUser`). Two signature layers are
  involved:

    * **inner signatures** — one per authorized signer, produced over the
      *payload* (`[multiSigUser, outerSigner, action]` for L1 actions, or the
      EIP-712 action extended with `payloadMultiSigUser`/`outerSigner` for
      user-signed actions). Inner signatures are *trimmed* (leading zeros of
      `r`/`s` removed) before being embedded in the wrapper.
    * **outer signature** — produced by the leader (the first signer, whose
      address is `outerSigner`) over the assembled wrapper using the
      `HyperliquidTransaction:SendMultiSig` EIP-712 struct.

  The wire shape of the wrapper is:

      %{
        "type" => "multiSig",
        "signatureChainId" => "0x66eee",
        "signatures" => [%{"r" => ..., "s" => ..., "v" => 27}, ...],
        "payload" => %{
          "multiSigUser" => "0x...",
          "outerSigner" => "0x...",
          "action" => %{...}
        }
      }

  ## Key order matters

  Both the inner and the outer hash are `keccak256` over a **msgpack** encoding
  of the action, so map key order is part of the hash. Every structure this
  module builds is a `Jason.OrderedObject`, and any `action` you pass in should
  be one too (or a map whose key order you control). See
  `Hyperliquid.Api.Exchange.UsdSend` for the same convention.

  ## Inner vs outer action (`payload_action`)

  The action that is *signed* by the inner signers may differ from the action
  that is *serialized into the wrapper payload*. The only action that currently
  needs this is `userSetAbstraction`, whose outer payload uses single-letter
  codes:

      "disabled"        -> "i"
      "unifiedAccount"  -> "u"
      "portfolioMargin" -> "p"

  `payload_action/1` performs that translation; `sign_user_signed/2` applies it
  automatically unless you pass an explicit `:payload_action`.

  ## Examples

      signers = ["0xleaderkey...", "0xsecondkey..."]

      # L1 action (orders, cancels, ...)
      {:ok, %{action: action, signature: sig, nonce: nonce}} =
        MultiSig.sign_l1(signers,
          multi_sig_user: "0x1234...",
          action: Jason.OrderedObject.new([{"type", "cancel"}, {"cancels", []}])
        )

      {:ok, resp} = MultiSig.send(action, sig, nonce)

  See https://hyperliquid.gitbook.io/hyperliquid-docs/hypercore/multi-sig
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @typedoc "A hex private key, with or without the `0x` prefix."
  @type private_key :: String.t()

  @typedoc "A hex `0x`-prefixed address."
  @type address :: String.t()

  @typedoc "An action body. Use `Jason.OrderedObject` to pin key order."
  @type action :: Jason.OrderedObject.t() | map() | list()

  @typedoc "EIP-712 type definitions, e.g. `[{\"HyperliquidTransaction:UsdSend\", [%{name: .., type: ..}]}]`."
  @type types :: Jason.OrderedObject.t() | map()

  @typedoc "An `r`/`s`/`v` signature."
  @type signature :: %{r: String.t(), s: String.t(), v: non_neg_integer()}

  @abstraction_codes %{
    "disabled" => "i",
    "unifiedAccount" => "u",
    "portfolioMargin" => "p"
  }

  # ── addresses ───────────────────────────────────────────────────────────────

  @doc """
  Returns the lowercased address that a private key derives to.

  The leader's address is the `outerSigner` of a multi-sig wrapper.
  """
  @spec outer_signer(private_key()) :: address()
  def outer_signer(private_key) when is_binary(private_key) do
    private_key |> Signer.derive_address() |> String.downcase()
  end

  # ── payload construction ────────────────────────────────────────────────────

  @doc """
  Builds the inner payload signed by each signer of an **L1** multi-sig action.

  The payload is the 3-element list `[multi_sig_user, outer_signer, action]`,
  with both addresses lowercased.
  """
  @spec build_payload(address(), address(), action()) :: [term()]
  def build_payload(multi_sig_user, outer_signer, action) do
    [String.downcase(multi_sig_user), String.downcase(outer_signer), action]
  end

  @doc """
  Builds the inner message/types pair signed by each signer of a **user-signed**
  (EIP-712) multi-sig action.

  `payloadMultiSigUser` and `outerSigner` are injected into the primary type
  immediately after its first field (this is what the exchange expects), and the
  matching values are prepended to the message.

  Returns `{message, extended_types}`, both `Jason.OrderedObject`s.
  """
  @spec build_user_signed_payload(address(), address(), action(), types()) ::
          {Jason.OrderedObject.t(), Jason.OrderedObject.t()}
  def build_user_signed_payload(multi_sig_user, outer_signer, action, types) do
    type_entries = ordered_entries(types)
    {primary_type, fields} = hd(type_entries)
    [first | rest] = fields

    extended_fields =
      [
        first,
        Jason.OrderedObject.new([{"name", "payloadMultiSigUser"}, {"type", "address"}]),
        Jason.OrderedObject.new([{"name", "outerSigner"}, {"type", "address"}])
      ] ++ rest

    extended_types =
      Jason.OrderedObject.new(
        Enum.map(type_entries, fn
          {^primary_type, _} -> {primary_type, extended_fields}
          other -> other
        end)
      )

    message =
      Jason.OrderedObject.new(
        [
          {"payloadMultiSigUser", String.downcase(multi_sig_user)},
          {"outerSigner", String.downcase(outer_signer)}
        ] ++ ordered_entries(action)
      )

    {message, extended_types}
  end

  # ── inner signatures ────────────────────────────────────────────────────────

  @doc """
  Produces one signer's **L1** inner signature over `payload`.

  `payload` is what `build_payload/3` returns.

  ## Options
    * `:nonce` — required, milliseconds since epoch (must match the outer nonce)
    * `:vault_address` — optional vault address used by the action
    * `:expires_after` — optional expiry (ms since epoch)
    * `:mainnet` — defaults to `Hyperliquid.Config.mainnet?/0`

  Returns a trimmed `%{r: .., s: .., v: ..}` map.
  """
  @spec sign_payload(private_key(), [term()], keyword()) :: signature()
  def sign_payload(private_key, payload, opts) when is_list(payload) and is_list(opts) do
    nonce = Keyword.fetch!(opts, :nonce)
    vault_address = Keyword.get(opts, :vault_address)
    expires_after = Keyword.get(opts, :expires_after)
    is_mainnet = Keyword.get_lazy(opts, :mainnet, &Config.mainnet?/0)

    connection_id =
      Signer.compute_connection_id_ex(
        Jason.encode!(payload),
        nonce,
        vault_address,
        expires_after
      )

    private_key
    |> Signer.sign_l1_action(connection_id, is_mainnet)
    |> to_signature()
    |> trim_signature()
  end

  @doc """
  Produces one signer's **user-signed** (EIP-712) inner signature.

  `message` and `types` are what `build_user_signed_payload/4` returns. The EIP-712 chain id
  is read from the message's `signatureChainId`.

  Returns a trimmed `%{r: .., s: .., v: ..}` map.
  """
  @spec sign_user_signed_payload(private_key(), Jason.OrderedObject.t(), types()) :: signature()
  def sign_user_signed_payload(private_key, message, types) do
    chain_id =
      message
      |> fetch_field!("signatureChainId")
      |> parse_chain_id()

    domain =
      Jason.OrderedObject.new([
        {"name", "HyperliquidSignTransaction"},
        {"version", "1"},
        {"chainId", chain_id},
        {"verifyingContract", "0x0000000000000000000000000000000000000000"}
      ])

    {primary_type, _} = types |> ordered_entries() |> hd()

    private_key
    |> Signer.sign_typed_data(
      Jason.encode!(domain),
      Jason.encode!(types),
      Jason.encode!(message),
      primary_type
    )
    |> to_signature()
    |> trim_signature()
  end

  # ── wrapper construction ────────────────────────────────────────────────────

  @doc """
  Assembles the outer `multiSig` action.

  `signatures` are the trimmed inner signatures (in signer order); `action` is
  the action as it should appear in the wrapper payload (see `payload_action/1`
  for the `userSetAbstraction` special case).
  """
  @spec build_action(String.t(), [signature()], address(), address(), action()) ::
          Jason.OrderedObject.t()
  def build_action(signature_chain_id, signatures, multi_sig_user, outer_signer, action) do
    Jason.OrderedObject.new([
      {"type", "multiSig"},
      {"signatureChainId", signature_chain_id},
      {"signatures", Enum.map(signatures, &signature_object/1)},
      {"payload",
       Jason.OrderedObject.new([
         {"multiSigUser", String.downcase(multi_sig_user)},
         {"outerSigner", String.downcase(outer_signer)},
         {"action", action}
       ])}
    ])
  end

  @doc """
  Signs the assembled wrapper with the leader's key.

  The `type` key is stripped before hashing (the exchange hashes the wrapper
  without its discriminator), then the `multiSigActionHash` is signed as
  `HyperliquidTransaction:SendMultiSig`.

  ## Options
    * `:nonce` — required, must equal the nonce used for the inner signatures
    * `:vault_address`, `:expires_after` — must match the inner signatures
    * `:mainnet` — defaults to `Hyperliquid.Config.mainnet?/0`

  Returns an untrimmed `%{r: .., s: .., v: ..}` map (the outer signature is sent
  in the normal `signature` field and is *not* trimmed).
  """
  @spec sign_action(private_key(), Jason.OrderedObject.t(), keyword()) :: signature()
  def sign_action(private_key, multi_sig_action, opts) do
    nonce = Keyword.fetch!(opts, :nonce)
    vault_address = Keyword.get(opts, :vault_address)
    expires_after = Keyword.get(opts, :expires_after)
    is_mainnet = Keyword.get_lazy(opts, :mainnet, &Config.mainnet?/0)

    without_type =
      multi_sig_action
      |> ordered_entries()
      |> Enum.reject(fn {k, _} -> k == "type" end)
      |> Jason.OrderedObject.new()

    private_key
    |> Signer.sign_multi_sig_action_ex(
      Jason.encode!(without_type),
      nonce,
      is_mainnet,
      vault_address,
      expires_after
    )
    |> to_signature()
  end

  # ── high level orchestration ────────────────────────────────────────────────

  @doc """
  Signs an L1 action for multi-sig execution.

  The first key in `signers` is the leader; its address becomes `outerSigner`
  and it produces the outer signature.

  ## Options
    * `:multi_sig_user` — required, the multi-sig account address
    * `:action` — required, the L1 action (use `Jason.OrderedObject`)
    * `:nonce` — defaults to `Hyperliquid.Utils.generate_nonce/0` (monotonic)
    * `:signature_chain_id` — defaults to `Hyperliquid.Config.signature_chain_id_hex/0`
    * `:vault_address` — optional
    * `:expires_after` — defaults to `Hyperliquid.Config.expires_after/0`
    * `:mainnet` — defaults to `Hyperliquid.Config.mainnet?/0`

  Returns `{:ok, %{action: wrapper, signature: sig, nonce: nonce}}`.
  """
  @spec sign_l1([private_key(), ...], keyword()) ::
          {:ok, %{action: Jason.OrderedObject.t(), signature: signature(), nonce: integer()}}
          | {:error, term()}
  def sign_l1([leader | _] = signers, opts) when is_list(signers) do
    multi_sig_user = Keyword.fetch!(opts, :multi_sig_user)
    # Canonicalize even when the caller handed us a plain map: the inner action
    # is msgpack-hashed, so its key order is part of the signature.
    action = Hyperliquid.Api.Exchange.Action.ordered(Keyword.fetch!(opts, :action))
    nonce = Keyword.get_lazy(opts, :nonce, &generate_nonce/0)
    vault_address = Keyword.get(opts, :vault_address)
    expires_after = Keyword.get_lazy(opts, :expires_after, &Config.expires_after/0)
    is_mainnet = Keyword.get_lazy(opts, :mainnet, &Config.mainnet?/0)

    signature_chain_id =
      Keyword.get_lazy(opts, :signature_chain_id, &Config.signature_chain_id_hex/0)

    outer_signer = outer_signer(leader)
    payload = build_payload(multi_sig_user, outer_signer, action)

    inner_opts = [
      nonce: nonce,
      vault_address: vault_address,
      expires_after: expires_after,
      mainnet: is_mainnet
    ]

    signatures = Enum.map(signers, &sign_payload(&1, payload, inner_opts))

    wrapper =
      build_action(signature_chain_id, signatures, multi_sig_user, outer_signer, action)

    signature = sign_action(leader, wrapper, inner_opts)

    {:ok, %{action: wrapper, signature: signature, nonce: nonce}}
  rescue
    e -> {:error, e}
  end

  @doc """
  Signs a user-signed (EIP-712) action for multi-sig execution.

  ## Options
    * `:multi_sig_user` — required
    * `:action` — required; must carry `signatureChainId`, `hyperliquidChain`
      and either `nonce` or `time`
    * `:types` — required EIP-712 type definitions for the action
    * `:payload_action` — the action serialized into the wrapper payload;
      defaults to `payload_action(action)`

  The network is taken from the action's `hyperliquidChain`, and the outer nonce
  from its `nonce`/`time`, so no vault or expiry applies here.

  Returns `{:ok, %{action: wrapper, signature: sig, nonce: nonce}}`.
  """
  @spec sign_user_signed([private_key(), ...], keyword()) ::
          {:ok, %{action: Jason.OrderedObject.t(), signature: signature(), nonce: integer()}}
          | {:error, term()}
  def sign_user_signed([leader | _] = signers, opts) when is_list(signers) do
    multi_sig_user = Keyword.fetch!(opts, :multi_sig_user)
    action = Keyword.fetch!(opts, :action)
    types = Keyword.fetch!(opts, :types)
    payload_action = Keyword.get_lazy(opts, :payload_action, fn -> payload_action(action) end)

    signature_chain_id = fetch_field!(action, "signatureChainId")
    nonce = fetch_field(action, "nonce") || fetch_field(action, "time")
    is_mainnet = fetch_field!(action, "hyperliquidChain") != "Testnet"

    outer_signer = outer_signer(leader)

    {message, extended_types} =
      build_user_signed_payload(multi_sig_user, outer_signer, action, types)

    signatures = Enum.map(signers, &sign_user_signed_payload(&1, message, extended_types))

    wrapper =
      build_action(
        signature_chain_id,
        signatures,
        multi_sig_user,
        outer_signer,
        payload_action
      )

    signature = sign_action(leader, wrapper, nonce: nonce, mainnet: is_mainnet)

    {:ok, %{action: wrapper, signature: signature, nonce: nonce}}
  rescue
    e -> {:error, e}
  end

  # ── sending ─────────────────────────────────────────────────────────────────

  @doc """
  POSTs a signed multi-sig wrapper to `/exchange`.

  `vault_address` and `expires_after` must be the same values used when signing.
  """
  @spec send(Jason.OrderedObject.t(), signature(), integer(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def send(multi_sig_action, signature, nonce, opts \\ []) do
    Http.exchange_request(
      multi_sig_action,
      signature,
      nonce,
      Keyword.get(opts, :vault_address),
      Keyword.get(opts, :expires_after),
      Keyword.drop(opts, [:vault_address, :expires_after])
    )
  end

  @doc """
  Signs (`sign_l1/2`) and sends an L1 multi-sig action in one call.
  """
  @spec request_l1([private_key(), ...], keyword()) :: {:ok, term()} | {:error, term()}
  def request_l1(signers, opts) do
    with {:ok, %{action: action, signature: signature, nonce: nonce}} <- sign_l1(signers, opts) do
      send(action, signature, nonce,
        vault_address: Keyword.get(opts, :vault_address),
        expires_after: Keyword.get_lazy(opts, :expires_after, &Config.expires_after/0)
      )
    end
  end

  @doc """
  Signs (`sign_user_signed/2`) and sends a user-signed multi-sig action.
  """
  @spec request_user_signed([private_key(), ...], keyword()) :: {:ok, term()} | {:error, term()}
  def request_user_signed(signers, opts) do
    with {:ok, %{action: action, signature: signature, nonce: nonce}} <-
           sign_user_signed(signers, opts) do
      send(action, signature, nonce)
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  @doc """
  Translates an inner (signed) action into the form embedded in the wrapper
  payload.

  Only `userSetAbstraction` differs: its `abstraction` field is emitted as the
  single-letter code (`"i"`, `"u"`, `"p"`). Every other action is returned
  unchanged.

  Note the SDK already carries both encodings:
  `Hyperliquid.Api.Exchange.UserSetAbstraction` uses the long form (inner) while
  `Hyperliquid.Api.Exchange.AgentSetAbstraction` uses the codes (outer).
  """
  @spec payload_action(action()) :: action()
  def payload_action(action) do
    entries = ordered_entries(action)

    case List.keyfind(entries, "type", 0) do
      {"type", "userSetAbstraction"} ->
        entries
        |> Enum.map(fn
          {"abstraction", value} -> {"abstraction", Map.get(@abstraction_codes, value, value)}
          other -> other
        end)
        |> Jason.OrderedObject.new()

      _ ->
        action
    end
  end

  @doc """
  Strips leading zeros from a signature's `r` and `s`.

  Multi-sig inner signatures are stored trimmed; because the wrapper is
  msgpack-hashed, an untrimmed signature changes the outer hash.
  """
  @spec trim_signature(signature()) :: signature()
  def trim_signature(%{r: r, s: s, v: v}), do: %{r: trim_hex(r), s: trim_hex(s), v: v}

  defp trim_hex("0x" <> rest), do: "0x" <> String.replace_leading(rest, "0", "")
  defp trim_hex(other), do: other

  defp signature_object(%{r: r, s: s, v: v}),
    do: Jason.OrderedObject.new([{"r", r}, {"s", s}, {"v", v}])

  defp to_signature(%{"r" => r, "s" => s, "v" => v}), do: %{r: r, s: s, v: v}

  defp to_signature(other),
    do: raise(ArgumentError, "signing failed: #{inspect(other)}")

  defp generate_nonce, do: Hyperliquid.Utils.generate_nonce()

  defp parse_chain_id("0x" <> hex), do: String.to_integer(hex, 16)
  defp parse_chain_id(int) when is_integer(int), do: int

  # Normalizes maps / OrderedObjects / keyword-ish lists to a `{string_key, value}` list.
  defp ordered_entries(%Jason.OrderedObject{values: values}), do: stringify_keys(values)
  defp ordered_entries(list) when is_list(list), do: stringify_keys(list)
  defp ordered_entries(map) when is_map(map), do: map |> Map.to_list() |> stringify_keys()

  defp stringify_keys(entries) do
    Enum.map(entries, fn {k, v} -> {to_string(k), v} end)
  end

  defp fetch_field(container, key) do
    case List.keyfind(ordered_entries(container), key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp fetch_field!(container, key) do
    fetch_field(container, key) ||
      raise ArgumentError, "action is missing required field #{inspect(key)}"
  end
end
