defmodule Hyperliquid.Api.Exchange.GossipPriorityBid do
  @moduledoc """
  Bid for a gossip priority slot.

  Priority slots let a specific IP submit gossip traffic ahead of other peers.
  There are two slots, addressed by `slot_id` 0 or 1.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/priority-fees

  ## Usage

      {:ok, result} = GossipPriorityBid.request(0, "1.2.3.4", 1_000_000)
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @max_slot_id 1

  @doc """
  Bid for a gossip priority slot.

  ## Parameters
    - `slot_id`: Priority slot, 0 or 1
    - `ip`: IPv4 or IPv6 address that should hold the slot
    - `max_gas`: Maximum gas to spend on the bid
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:vault_address` - Act on behalf of a vault

  ## Returns
    - `{:ok, response}` - Bid result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = GossipPriorityBid.request(0, "1.2.3.4", 1_000_000)
  """
  @spec request(non_neg_integer(), String.t(), non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def request(slot_id, ip, max_gas, opts \\ [])
      when is_integer(slot_id) and is_binary(ip) and is_integer(max_gas) do
    validate_slot_id!(slot_id)
    validate_ip!(ip)

    if max_gas < 0 do
      raise ArgumentError, "max_gas must be non-negative, got: #{inspect(max_gas)}"
    end

    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = %{
      type: "gossipPriorityBid",
      slotId: slot_id,
      ip: ip,
      maxGas: max_gas
    }

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after) do
      Http.exchange_request(action, signature, nonce, vault_address, expires_after, opts)
    end
  end

  defp validate_slot_id!(slot_id) when slot_id >= 0 and slot_id <= @max_slot_id, do: :ok

  defp validate_slot_id!(slot_id) do
    raise ArgumentError,
          "slot_id must be between 0 and #{@max_slot_id}, got: #{inspect(slot_id)}"
  end

  defp validate_ip!(ip) do
    case ip |> String.to_charlist() |> :inet.parse_address() do
      {:ok, _} -> :ok
      {:error, _} -> raise ArgumentError, "ip must be a valid IP address, got: #{inspect(ip)}"
    end
  end

  defp sign_action(private_key, action_json, nonce, vault_address, expires_after) do
    is_mainnet = Config.mainnet?()

    connection_id =
      Signer.compute_connection_id_ex(action_json, nonce, vault_address, expires_after)

    case Signer.sign_l1_action(private_key, connection_id, is_mainnet) do
      %{"r" => r, "s" => s, "v" => v} -> {:ok, %{r: r, s: s, v: v}}
      error -> {:error, {:signing_error, error}}
    end
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
