defmodule Hyperliquid do
  @moduledoc """
  Top-level entry point for the Hyperliquid Elixir SDK.

  Most work happens in the context modules:

  - `Hyperliquid.Api.Info` — read-only market and account data
  - `Hyperliquid.Api.Exchange` — trading and account actions
  - `Hyperliquid.Api.Subscription.*` — WebSocket channels
  - `Hyperliquid.Api.Registry` — endpoint discovery/introspection
  - `Hyperliquid.Api.MultiSig` — multi-sig wrapping of any of the above actions

  A handful of top-level shortcuts are exposed here for the paths that do not
  belong to a single context module.
  """

  @doc """
  Sign and send an L1 action wrapped in a `multiSig` action.

  Delegates to `Hyperliquid.Api.MultiSig.request_l1/2`.

  ## Examples

      Hyperliquid.multi_sig_l1([leader_key, second_key],
        multi_sig_user: "0x...",
        action: Jason.OrderedObject.new([{"type", "cancel"}, {"cancels", []}])
      )
  """
  defdelegate multi_sig_l1(signers, opts), to: Hyperliquid.Api.MultiSig, as: :request_l1

  @doc """
  Sign and send a user-signed (EIP-712) action wrapped in a `multiSig` action.

  Delegates to `Hyperliquid.Api.MultiSig.request_user_signed/2`.
  """
  defdelegate multi_sig_user_signed(signers, opts),
    to: Hyperliquid.Api.MultiSig,
    as: :request_user_signed

  @doc """
  Hello world.

  ## Examples

      iex> Hyperliquid.hello()
      :world

  """
  def hello do
    :world
  end
end
