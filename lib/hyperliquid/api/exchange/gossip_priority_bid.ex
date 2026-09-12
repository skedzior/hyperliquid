defmodule Hyperliquid.Api.Exchange.GossipPriorityBid do
  @moduledoc """
  Bid for a gossip priority slot.

  L1-signed.

      {"type":"gossipPriorityBid","slotId":<0|1>,"ip":"<ipv4/ipv6>","maxGas":<uint>}

  Auction status is readable via the `gossipPriorityAuctionStatus` info endpoint.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @doc """
  Place a gossip priority bid.

  ## Parameters
    - `slot_id`: Slot identifier, `0` or `1`
    - `ip`: IP address string
    - `max_gas`: Maximum gas to bid (integer)
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  @max_slot_id 1

  def request(slot_id, ip, max_gas, opts \\ [])
      when is_integer(slot_id) and is_binary(ip) and is_integer(max_gas) do
    unless slot_id in 0..@max_slot_id do
      raise ArgumentError,
            "slot_id must be between 0 and #{@max_slot_id}, got: #{inspect(slot_id)}"
    end

    validate_ip!(ip)

    if max_gas < 0 do
      raise ArgumentError, "max_gas must be non-negative, got: #{inspect(max_gas)}"
    end

    send_action(build_action(slot_id, ip, max_gas), opts)
  end

  @doc false
  # Exposed for tests: builds the signed action without performing IO.
  # IMPORTANT: OrderedObject preserves key order for the L1 action hash.
  def build_action(slot_id, ip, max_gas) do
    Jason.OrderedObject.new([
      {:type, "gossipPriorityBid"},
      {:slotId, slot_id},
      {:ip, ip},
      {:maxGas, max_gas}
    ])
  end

  defp send_action(action, opts) do
    private_key = KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = Hyperliquid.Utils.generate_nonce()
    expires_after = Config.expires_after()

    action = Hyperliquid.Api.Exchange.Action.ordered(action)

    with {:ok, action_json} <- Jason.encode(action),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after) do
      Http.exchange_request(action, signature, nonce, vault_address, expires_after, opts)
    end
  end

  defp sign_action(private_key, action_json, nonce, vault_address, expires_after) do
    Hyperliquid.Api.Exchange.Action.sign_json(
      private_key,
      action_json,
      nonce,
      vault_address,
      expires_after
    )
  end

  defp validate_ip!(ip) do
    case ip |> String.to_charlist() |> :inet.parse_address() do
      {:ok, _} -> :ok
      {:error, _} -> raise ArgumentError, "ip must be a valid IP address, got: #{inspect(ip)}"
    end
  end
end
