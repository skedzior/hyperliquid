defmodule Hyperliquid.Encoder do
  @moduledoc """
  manual encoding methods to support structured data
  """
  alias Hyperliquid.Utils
  import Msgpax

  @action_type pack!("type")

  @action_types %{
    order: pack!("order"),
    cancel: pack!("cancel"),
    cancelByCloid: pack!("cancelByCloid"),
    modify: pack!("modify"),
    batchModify: pack!("batchModify"),
    updateLeverage: pack!("updateLeverage"),
    updateIsolatedMargin: pack!("updateIsolatedMargin"),
    spotUser: pack!("spotUser"),
    vaultTransfer: pack!("vaultTransfer"),
    createSubAccount: pack!("createSubAccount"),
    subAccountTransfer: pack!("subAccountTransfer"),
    subAccountSpotTransfer: pack!("subAccountSpotTransfer")
  }

  @orders pack!("orders")
  @cancels pack!("cancels")
  @modifies pack!("modifies")
  @oid pack!("oid")
  @order pack!("order")
  @class_transfer pack!("classTransfer")

  @fields %{
    a: pack!("a"),
    b: pack!("b"),
    p: pack!("p"),
    s: pack!("s"),
    r: pack!("r"),
    t: pack!("t"),
    o: pack!("o"),
    c: pack!("c"),
    asset: pack!("asset"),
    cloid: pack!("cloid"),
    isMarket: pack!("isMarket"),
    triggerPx: pack!("triggerPx"),
    tpsl: pack!("tpsl"),
    trigger: pack!("trigger"),
    limit: pack!("limit"),
    usdc: pack!("usdc"),
    toPerp: pack!("toPerp"),
    vaultAddress: pack!("vaultAddress"),
    isDeposit: pack!("isDeposit"),
    usd: pack!("usd"),
    hyperliquidChain: pack!("hyperliquidChain"),
    signatureChainId: pack!("signatureChainId"),
    token: pack!("token"),
    amount: pack!("amount"),
    time: pack!("time"),
    chain: pack!("chain"),
    isBuy: pack!("isBuy"),
    ntli: pack!("ntli"),
    isCross: pack!("isCross"),
    leverage: pack!("leverage"),
    subAccountUser: pack!("subAccountUser"),
    name: pack!("name")
  }

  @grouping pack!("grouping")

  @groupings %{
    "na" => pack!("na"),
    "normalTpsl" => pack!("normalTpsl"),
    "positionTpsl" => pack!("positionTpsl")
  }

  def type(key), do: [@action_type | @action_types[key]]

  def grouping(key), do: [@grouping | @groupings[key]]

  def field(:t, %{t: %{trigger: _}} = value), do: [@fields[:t] | pack_trigger(value[:t])]
  def field(key, value), do: [@fields[key] | pack!(value[key])]
  def fields([_|_] = keys, value), do: Enum.map(keys, &field(&1, value))

  def pack_orders(orders) do
    Enum.reduce(orders, [@orders, first_byte(orders)], &(&2 ++ pack_order(&1)))
  end

  def pack_order(order) do
    bytes = [first_byte(order) | fields([:a, :b, :p, :s, :r, :t], order)]

    case Map.has_key?(order, :c) do
      true -> [bytes ++ field(:c, order)]
      _ -> bytes
    end
  end

  def pack_trigger(t) do
    [
      first_byte(t),
      @fields[:trigger],
      first_byte(t[:trigger]),
      fields([:isMarket, :triggerPx, :tpsl], t[:trigger])
    ]
  end

  def pack_cancel(%{cloid: _} = cancel) do
    [first_byte(cancel), fields([:asset, :cloid], cancel)]
  end

  def pack_cancel(cancel) do
    [first_byte(cancel), fields([:a, :o], cancel)]
  end

  def pack_cancels(cancels) do
    Enum.reduce(cancels, [@cancels, first_byte(cancels)], &(&2 ++ pack_cancel(&1)))
  end

  def pack_modifies(modifies) do
    Enum.reduce(modifies, [@modifies, first_byte(modifies)], &(&2 ++ [first_byte(&1) | pack_modify(&1)]))
  end

  def pack_modify(mod) do
    [@oid, pack!(mod[:oid]), @order] ++ pack_order(mod[:order])
  end

  def pack_transfer(transfer) do
    [
      @class_transfer,
      first_byte(transfer),
      fields([:usdc, :toPerp], transfer)
    ]
  end

  def pack_action(%{type: "updateLeverage"} = action, nonce, vault_address) do
    [
      first_byte(action),
      type(:updateLeverage),
      fields([:asset, :isCross, :leverage], action),
      add_additional_bytes(nonce, vault_address)
    ]
  end

  def pack_action(%{type: "createSubAccount"} = action, nonce, vault_address) do
    [
      first_byte(action),
      type(:createSubAccount),
      field(:name, action),
      add_additional_bytes(nonce, vault_address)
    ]
  end

  def pack_action(%{type: "subAccountTransfer"} = action, nonce, vault_address) do
    [
      first_byte(action),
      type(:subAccountTransfer),
      fields([:subAccountUser, :isDeposit, :usd], action),
      add_additional_bytes(nonce, vault_address)
    ]
  end

  def pack_action(%{type: "subAccountSpotTransfer"} = action, nonce, vault_address) do
    [
      first_byte(action),
      type(:subAccountSpotTransfer),
      fields([:subAccountUser, :isDeposit, :token, :amount], action),
      add_additional_bytes(nonce, vault_address)
    ]
  end

  def pack_action(%{type: "updateIsolatedMargin"} = action, nonce, vault_address) do
    [
      first_byte(action),
      type(:updateIsolatedMargin),
      fields([:asset, :isBuy, :ntli], action),
      add_additional_bytes(nonce, vault_address)
    ]
  end

  def pack_action(%{type: "vaultTransfer"} = action, nonce, vault_address) do
    [
      first_byte(action),
      type(:vaultTransfer),
      fields([:vaultAddress, :isDeposit, :usd], action),
      add_additional_bytes(nonce, vault_address)
    ]
  end

  def pack_action(%{type: "order"} = action, nonce, vault_address) do
    [
      first_byte(action),
      type(:order),
      pack_orders(action[:orders]),
      grouping(action[:grouping]),
      add_additional_bytes(nonce, vault_address)
    ]
  end

  def pack_action(%{type: "cancel"} = action, nonce, vault_address) do
    [
      first_byte(action),
      type(:cancel),
      pack_cancels(action[:cancels]),
      add_additional_bytes(nonce, vault_address)
    ]
  end

  def pack_action(%{type: "cancelByCloid"} = action, nonce, vault_address) do
    [
      first_byte(action),
      type(:cancelByCloid),
      pack_cancels(action[:cancels]),
      add_additional_bytes(nonce, vault_address)
    ]
  end

  def pack_action(%{type: "modify"} = action, nonce, vault_address) do
    [
      first_byte(action),
      type(:modify),
      pack_modify(action),
      add_additional_bytes(nonce, vault_address)
    ]
  end

  def pack_action(%{type: "batchModify"} = action, nonce, vault_address) do
    [
      first_byte(action),
      type(:batchModify),
      pack_modifies(action[:modifies]),
      add_additional_bytes(nonce, vault_address)
    ]
  end

  def pack_action(%{type: "spotUser"} = action, nonce, vault_address) do
    [
      first_byte(action),
      type(:spotUser),
      pack_transfer(action[:classTransfer]),
      add_additional_bytes(nonce, vault_address)
    ]
  end

  def first_byte(action), do: pack!(action) |> Enum.take(1)
  def first_byte(action, false), do: first_byte(action) |> to_binary()

  def to_binary(data), do: IO.iodata_to_binary(data)

  def address_to_bytes(address) do
    Utils.trim_0x(address)
    |> Base.decode16(case: :lower)
    |> case do
      {:ok, binary} -> binary
      {:error, _reason} -> raise "Invalid hexadecimal string"
    end
  end

  def add_additional_bytes(nonce, nil) do
    nonce_position = byte_size(<<>>)

    <<>> <> <<0::size(8 * 9)>>
    |> put_big_uint64(nonce, nonce_position)
    |> put_uint8(0, nonce_position + 8)
  end

  def add_additional_bytes(nonce, vault_address) do
    address_bytes = address_to_bytes(vault_address)
    nonce_position = byte_size(<<>>)

    <<>> <> <<0::size(8 * 29)>>
    |> put_big_uint64(nonce, nonce_position)
    |> put_uint8(1, nonce_position + 8)
    |> put_bytes(address_bytes, nonce_position + 9)
  end

  def put_big_uint64(data, value, position) do
    <<head::binary-size(position), _::binary-size(8), tail::binary>> = data
    <<head::binary, value::big-integer-size(64), tail::binary>>
  end

  def put_uint8(data, value, position) do
    <<head::binary-size(position), _::size(8), tail::binary>> = data
    <<head::binary, value::integer-size(8), tail::binary>>
  end

  def put_bytes(data, bytes, position) do
    <<head::binary-size(position), _::binary-size(byte_size(bytes)), tail::binary>> = data
    <<head::binary, bytes::binary, tail::binary>>
  end
end
