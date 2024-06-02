defmodule HyperliquidTest do
  use ExUnit.Case
  doctest Hyperliquid

  test "greets the world" do
    assert Hyperliquid.hello() == :world
  end
end
