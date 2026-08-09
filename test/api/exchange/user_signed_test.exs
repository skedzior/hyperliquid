defmodule Hyperliquid.Api.Exchange.UserSignedTest do
  @moduledoc """
  Guards the invariant that the EIP-712 domain a user-signed action is signed
  over always matches the `signatureChainId` sent in its body.

  The exchange rebuilds the domain from `signatureChainId` to recover the signer,
  so if the two drift it recovers the wrong address and rejects the action. That
  is exactly what happened before e0e67bf, when the domain was hardcoded while
  `signatureChainId` varied by network.
  """
  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.{
    ApproveAgent,
    ApproveBuilderFee,
    SpotSend,
    UsdSend,
    UserSigned,
    Withdraw3
  }

  alias Hyperliquid.{Config, Signer}

  @private_key "0x822e9959e022b78423eb653a62ea0020cd283e71a2a8133a6ff2aeffaf373cff"
  @address "0x1234567890123456789012345678901234567890"

  setup do
    bypass = Bypass.open()
    prev_url = Application.get_env(:hyperliquid, :http_url)
    Application.put_env(:hyperliquid, :http_url, "http://localhost:#{bypass.port}")

    test_pid = self()

    Bypass.stub(bypass, "POST", "/exchange", fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:body, Jason.decode!(raw)})

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"status" => "ok"}))
    end)

    on_exit(fn ->
      if prev_url,
        do: Application.put_env(:hyperliquid, :http_url, prev_url),
        else: Application.delete_env(:hyperliquid, :http_url)

      Application.delete_env(:hyperliquid, :signature_chain_id)
    end)

    {:ok, bypass: bypass}
  end

  describe "domain and signatureChainId agree" do
    test "the domain chainId is the numeric form of signatureChainId" do
      assert UserSigned.domain().chainId == Config.signature_chain_id()

      # Lowercase hex — the docs spell it "0xa4b1", and an uppercase form was one
      # of the bugs fixed in e0e67bf.
      assert UserSigned.signature_chain_id() ==
               "0x" <> String.downcase(Integer.to_string(Config.signature_chain_id(), 16))

      assert UserSigned.signature_chain_id() ==
               String.downcase(UserSigned.signature_chain_id())
    end

    test "usdSend sends the configured signatureChainId" do
      assert {:ok, _} = UsdSend.request(@address, "1", private_key: @private_key)
      assert_sent_chain_id()
    end

    test "withdraw3 sends the configured signatureChainId" do
      assert {:ok, _} = Withdraw3.request(@address, "1", private_key: @private_key)
      assert_sent_chain_id()
    end

    test "spotSend sends the configured signatureChainId" do
      assert {:ok, _} = SpotSend.request(@address, "USDC", "1", private_key: @private_key)
      assert_sent_chain_id()
    end

    test "approveBuilderFee sends the configured signatureChainId" do
      assert {:ok, _} = ApproveBuilderFee.request(@address, "0.001", private_key: @private_key)
      assert_sent_chain_id()
    end

    test "approveAgent sends the configured signatureChainId" do
      assert {:ok, _} = ApproveAgent.approve(@address, private_key: @private_key)
      assert_sent_chain_id()
    end
  end

  defp assert_sent_chain_id do
    assert_receive {:body, body}
    assert body["action"]["signatureChainId"] == Config.signature_chain_id_hex()
  end

  describe "configuration propagates" do
    test "overriding signature_chain_id changes both the domain and the body" do
      Application.put_env(:hyperliquid, :signature_chain_id, 1)

      assert UserSigned.domain().chainId == 1
      assert UserSigned.signature_chain_id() == "0x1"

      assert {:ok, _} = UsdSend.request(@address, "1", private_key: @private_key)

      assert_receive {:body, body}
      assert body["action"]["signatureChainId"] == "0x1"
    end

    test "a different chain id produces a different signature" do
      Application.put_env(:hyperliquid, :signature_chain_id, 421_614)
      {:ok, a} = UserSigned.sign(@private_key, "T", [%{name: "x", type: "string"}], %{x: "1"})

      Application.put_env(:hyperliquid, :signature_chain_id, 42_161)
      {:ok, b} = UserSigned.sign(@private_key, "T", [%{name: "x", type: "string"}], %{x: "1"})

      refute a.r == b.r
    end
  end

  describe "the Rust NIF agrees with the generic typed-data path" do
    # The specialized NIFs build the EIP-712 domain in Rust, while everything
    # else builds it from Config. These must not diverge — if this fails after a
    # Config change, the NIF needs rebuilding to match.
    test "sign_usd_send matches UserSigned.sign/4" do
      time = 1_234_567_890

      nif = Signer.sign_usd_send(@private_key, @address, "1000", time, true)

      {:ok, generic} =
        UserSigned.sign(
          @private_key,
          "HyperliquidTransaction:UsdSend",
          [
            %{name: "hyperliquidChain", type: "string"},
            %{name: "destination", type: "string"},
            %{name: "amount", type: "string"},
            %{name: "time", type: "uint64"}
          ],
          %{hyperliquidChain: "Mainnet", destination: @address, amount: "1000", time: time}
        )

      assert nif["r"] == generic.r
      assert nif["s"] == generic.s
      assert nif["v"] == generic.v
    end

    test "sign_spot_send matches UserSigned.sign/4" do
      time = 1_234_567_890

      nif = Signer.sign_spot_send(@private_key, @address, "USDC", "1000", time, true)

      {:ok, generic} =
        UserSigned.sign(
          @private_key,
          "HyperliquidTransaction:SpotSend",
          [
            %{name: "hyperliquidChain", type: "string"},
            %{name: "destination", type: "string"},
            %{name: "token", type: "string"},
            %{name: "amount", type: "string"},
            %{name: "time", type: "uint64"}
          ],
          %{
            hyperliquidChain: "Mainnet",
            destination: @address,
            token: "USDC",
            amount: "1000",
            time: time
          }
        )

      assert nif["r"] == generic.r
    end
  end
end
