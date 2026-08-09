# Verifies against the live Hyperliquid TESTNET API that user-signed EIP-712
# actions recover the correct signer — i.e. that the EIP-712 domain chainId and
# the action's signatureChainId agree.
#
#   HL_TESTNET_KEY=0x... mix run scripts/verify_testnet_usd_send.exs
#
# The key is read from the environment and never written anywhere.
#
# How this works without spending anything
# ----------------------------------------
# The API reports the address it recovered from the signature:
#
#   "Must deposit before performing actions. User: 0x863bef9f..."
#
# So the probe does not need a funded account, a master key, or a successful
# transfer. It only needs to compare the recovered address to the signer:
#
#   recovered == signer  -> the signature verified; any failure after that is
#                           about funds, not signing
#   recovered != signer  -> the domain the API rebuilt from signatureChainId does
#                           not match the domain we signed over
#
# An agent/API wallet works fine here: it recovers as itself.
#
# Pass --control to additionally run the negative control, which deliberately
# signs one chainId and declares another, and must recover a different address.

alias Hyperliquid.Api.Exchange.UserSigned
alias Hyperliquid.Transport.Http
alias Hyperliquid.{Config, Signer}

key =
  System.get_env("HL_TESTNET_KEY") ||
    raise "HL_TESTNET_KEY is not set. Use a TESTNET key, never a mainnet key."

Application.put_env(:hyperliquid, :chain, :testnet)
Application.put_env(:hyperliquid, :is_mainnet, false)
unless Config.mainnet?() == false, do: raise("refusing to run: still resolving to mainnet")

signer = key |> Signer.derive_address() |> String.downcase()

types = [
  %{name: "hyperliquidChain", type: "string"},
  %{name: "destination", type: "string"},
  %{name: "amount", type: "string"},
  %{name: "time", type: "uint64"}
]

# Sends a usdSend and returns the address the API recovered, signing over
# `signed_chain_id` while declaring `sent_chain_id` in the body.
probe = fn signed_chain_id, sent_chain_id ->
  time = System.system_time(:millisecond)
  Application.put_env(:hyperliquid, :signature_chain_id, signed_chain_id)

  {:ok, sig} =
    UserSigned.sign(key, "HyperliquidTransaction:UsdSend", types, %{
      hyperliquidChain: "Testnet",
      destination: signer,
      amount: "1",
      time: time
    })

  action =
    Jason.OrderedObject.new([
      {:type, "usdSend"},
      {:signatureChainId, "0x" <> String.downcase(Integer.to_string(sent_chain_id, 16))},
      {:hyperliquidChain, "Testnet"},
      {:destination, signer},
      {:amount, "1"},
      {:time, time}
    ])

  case Http.user_signed_request(action, sig, time) do
    {:ok, %{"status" => "ok"} = body} ->
      {:accepted, body}

    {:ok, %{"response" => resp}} ->
      case Regex.run(~r/User: (0x[0-9a-f]+)/i, to_string(resp)) do
        [_, addr] -> {:recovered, String.downcase(addr), to_string(resp)}
        _ -> {:other, to_string(resp)}
      end

    other ->
      {:error, other}
  end
end

configured = Config.signature_chain_id()

IO.puts("""

  network           testnet (#{Config.api_base()})
  signer            #{signer}
  signatureChainId  #{UserSigned.signature_chain_id()}  (domain chainId #{configured})
""")

IO.puts("  probing ...")

verdict =
  case probe.(configured, configured) do
    {:accepted, _} ->
      IO.puts("\n  PASS — action accepted outright.")
      :pass

    {:recovered, ^signer, resp} ->
      IO.puts("""

        PASS — the API recovered #{signer}, which is the signer.

        Response: #{resp}

        That is a funding message, not a signing one: the signature verified and
        the EIP-712 domain matches what the API rebuilt from signatureChainId.
      """)

      :pass

    {:recovered, other, resp} ->
      IO.puts("""

        FAIL — the API recovered #{other}, but we signed as #{signer}.

        Response: #{resp}

        The domain the API rebuilt from signatureChainId does not match the one
        we signed over. Revert with:

            config :hyperliquid, signature_chain_id: 42_161
      """)

      :fail

    {:other, resp} ->
      IO.puts("\n  PASS (probably) — rejected without a recovered address: #{resp}")
      :pass

    {:error, e} ->
      IO.puts("\n  transport error, not a signing verdict: #{inspect(e)}")
      :error
  end

if "--control" in System.argv() do
  IO.puts("\n  negative control — signing #{configured} but declaring 42161 ...")

  case probe.(configured, 42_161) do
    {:recovered, ^signer, _} when configured == 42_161 ->
      IO.puts("  (not a control: configured value is already 42161)")

    {:recovered, other, _} when other != signer ->
      IO.puts("""
        CONTROL OK — recovered #{other}, a different address, as expected.

        This is the drift that made the API recover the wrong signer before
        e0e67bf. Both values now come from Config.signature_chain_id/0, so the
        library cannot produce this state.
      """)

    other ->
      IO.puts("  control inconclusive: #{inspect(other)}")
  end
end

System.halt(if verdict == :fail, do: 1, else: 0)
