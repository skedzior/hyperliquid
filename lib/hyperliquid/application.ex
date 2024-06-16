defmodule Hyperliquid.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @cache :hyperliquid

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Hyperliquid.PubSub},
      {Cachex, name: @cache}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hyperliquid.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
