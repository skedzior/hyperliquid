defmodule Hyperliquid.Signer do
  alias Hyperliquid.Encoder
  import Hyperliquid.Utils

  @zero_address "0x0000000000000000000000000000000000000000"

  def action_hash(action, nonce, vault_address) do
    Encoder.pack_action(action, nonce, vault_address)
    |> IO.iodata_to_binary()
    |> ExKeccak.hash_256()
    |> Base.encode16(case: :lower)
    |> then(&("0x" <> &1))
  end

  # Constructs a phantom agent
  def construct_phantom_agent(hash, mainnet?) do
    source = if(mainnet?, do: "a", else: "b")
    %{"source" => source, "connectionId" => hash}
  end

  # Signs an L1 action
  def sign_l1_action(action, vault_address, nonce, mainnet?, secret) do
    hash = action_hash(action, nonce, vault_address)
    phantom_agent = construct_phantom_agent(hash, mainnet?)
    data = prepare_data(phantom_agent, 1337)

    case EIP712.sign(data, trim_0x(secret)) do
      {:ok, hex_signature} -> split_sig(hex_signature)
      resp -> IO.inspect(resp, label: "fucking rwesp")
    end
  end

  def prepare_data(message, chain_id) do
    Jason.encode! %{
      domain: %{
        chainId: to_full_hex(chain_id),
        name: "Exchange",
        verifyingContract: @zero_address,
        version: "1"
      },
      types: %{
        Agent: [
          %{name: "source", type: "string"},
          %{name: "connectionId", type: "bytes32"}
        ],
        EIP712Domain: [
          %{name: "name", type: "string"},
          %{name: "version", type: "string"},
          %{name: "chainId", type: "uint256"},
          %{name: "verifyingContract", type: "address"}
        ]
      },
      primaryType: "Agent",
      message: message
    }
  end

  def sign_user_signed_action(action, payload_types, primary_type, mainnet?, secret) do
    chain_id = if(mainnet?, do: to_hex(42_161), else: to_hex(421_614))
    action =
      Map.merge(action, %{
        hyperliquidChain: if(mainnet?, do: "Mainnet", else: "Testnet"),
        signatureChainId: chain_id,
        time: to_hex(action.time)
      })

    data = Jason.encode! %{
      domain: %{
        name: "HyperliquidSignTransaction",
        version: "1",
        chainId: chain_id,
        verifyingContract: @zero_address
      },
      types: %{
        "#{primary_type}": payload_types,
        EIP712Domain: [
          %{name: "name", type: "string"},
          %{name: "version", type: "string"},
          %{name: "chainId", type: "uint256"},
          %{name: "verifyingContract", type: "address"}
        ]
      },
      primaryType: primary_type,
      message: action
    }

    case EIP712.sign(data, trim_0x(secret)) do
      {:ok, hex_signature} -> split_sig(hex_signature)
      resp -> IO.inspect(resp, label: "fucking rwesp")
    end
  end

  def sign_spot_transfer_action(action, mainnet?, secret) do
    sign_user_signed_action(
      action,
      [
        %{name: "hyperliquidChain", type: "string"},
        %{name: "destination", type: "string"},
        %{name: "token", type: "string"},
        %{name: "amount", type: "string"},
        %{name: "time", type: "uint64"},
      ],
      "HyperliquidTransaction:SpotSend",
      mainnet?,
      secret
    )
  end

  def sign_usd_transfer_action(action, mainnet?, secret) do
    sign_user_signed_action(
      action,
      [
        %{name: "hyperliquidChain", type: "string"},
        %{name: "destination", type: "string"},
        %{name: "amount", type: "string"},
        %{name: "time", type: "uint64"},
      ],
      "HyperliquidTransaction:UsdSend",
      mainnet?,
      secret
    )
  end

  def sign_withdraw_from_bridge_action(action, mainnet?, secret) do
    sign_user_signed_action(
      action,
      [
        %{name: "hyperliquidChain", type: "string"},
        %{name: "destination", type: "string"},
        %{name: "amount", type: "string"},
        %{name: "time", type: "uint64"},
      ],
      "HyperliquidTransaction:Withdraw",
      mainnet?,
      secret
    )
  end

  def sign_agent(action, mainnet?, secret) do
    # testnet signaturechainid = to_hex(43114)
    sign_user_signed_action(
      action,
      [
        %{name: "hyperliquidChain", type: "string"},
        %{name: "agentAddress", type: "address"},
        %{name: "agentName", type: "string"},
        %{name: "nonce", type: "uint64"}
      ],
      "HyperliquidTransaction:ApproveAgent",
      mainnet?,
      secret
    )
  end

  # Signs the structured data
  def split_sig(hex_signature) do
    hex_signature = trim_0x(hex_signature)

    if String.length(hex_signature) != 130 do
      raise ArgumentError, "bad sig length: #{String.length(hex_signature)}"
    end

    sig_v = String.slice(hex_signature, -2, 2)

    unless sig_v in ["1c", "1b", "00", "01"] do
      raise ArgumentError, "bad sig v #{sig_v}"
    end

    v_value =
      case sig_v do
        "1b" -> 27
        "00" -> 27
        "1c" -> 28
        "01" -> 28
        _ -> raise("Unexpected sig_v value")
      end

    r = "0x" <> String.slice(hex_signature, 0, 64)
    s = "0x" <> String.slice(hex_signature, 64, 64)

    %{r: r, s: s, v: v_value}
  end
end
