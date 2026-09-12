defmodule Hyperliquid.WebSocket.PackerTest do
  use ExUnit.Case, async: true

  alias Hyperliquid.WebSocket.Packer

  @url "wss://api.hyperliquid.xyz/ws"

  defp conn(key), do: Packer.new_connection(key, @url)

  defp user_demand(user, opts \\ []) do
    %{url: @url, user: user, group_a?: Keyword.get(opts, :group_a?, false)}
  end

  defp market_demand, do: %{url: @url, user: nil, group_a?: false}

  describe "packing math" do
    test "packs 15 unique users onto one connection, then opens a second" do
      opts = [max_users_per_connection: 15, max_connections: 10]

      {slots, opened} =
        Enum.reduce(1..20, {[conn("c1")], 1}, fn n, {slots, opened} ->
          demand = user_demand("0xuser#{n}")

          case Packer.place(slots, demand, 0, opts) do
            {:ok, key} ->
              slots =
                Enum.map(slots, fn s -> if s.key == key, do: Packer.add(s, demand), else: s end)

              {slots, opened}

            :new ->
              new = "c#{opened + 1}" |> conn() |> Packer.add(demand)
              {slots ++ [new], opened + 1}
          end
        end)

      assert opened == 2
      [first, second] = slots
      assert MapSet.size(first.users) == 15
      assert MapSet.size(second.users) == 5
      assert first.subscriptions == 15
      assert second.subscriptions == 5
    end

    test "several subscriptions for the same user consume a single slot" do
      opts = [max_users_per_connection: 2]
      demand = user_demand("0xa")

      slot =
        conn("c1")
        |> Packer.add(demand)
        |> Packer.add(demand)
        |> Packer.add(demand)

      assert MapSet.size(slot.users) == 1
      assert slot.subscriptions == 3
      assert Packer.has_headroom?(slot, user_demand("0xb"), 0, opts)
    end

    test "market subscriptions never consume a user slot" do
      opts = [max_users_per_connection: 1]
      slot = Packer.add(conn("c1"), user_demand("0xa"))

      assert Packer.has_headroom?(slot, market_demand(), 0, opts)
      refute Packer.has_headroom?(slot, user_demand("0xb"), 0, opts)
    end

    test "a full connection is skipped and the fullest non-full one is preferred" do
      opts = [max_users_per_connection: 2]

      full = conn("full") |> Packer.add(user_demand("0xa")) |> Packer.add(user_demand("0xb"))
      half = Packer.add(conn("half"), user_demand("0xc"))
      empty = conn("empty")

      assert {:ok, "half"} = Packer.place([full, half, empty], user_demand("0xd"), 0, opts)
    end

    test "prefers the connection that already tracks the user" do
      opts = [max_users_per_connection: 5]

      fuller =
        conn("fuller") |> Packer.add(user_demand("0xa")) |> Packer.add(user_demand("0xb"))

      mine = Packer.add(conn("mine"), user_demand("0xz"))

      assert {:ok, "mine"} = Packer.place([fuller, mine], user_demand("0xz"), 0, opts)
    end

    test "refuses when every connection is full and the connection budget is spent" do
      opts = [max_users_per_connection: 1, max_connections: 2]
      c1 = Packer.add(conn("c1"), user_demand("0xa"))
      c2 = Packer.add(conn("c2"), user_demand("0xb"))

      assert {:error, :connection_limit_exceeded} =
               Packer.place([c1, c2], user_demand("0xc"), 0, opts)
    end

    test "connections for other URLs are not candidates" do
      other = %{Packer.new_connection("other", "wss://other.example/ws") | subscriptions: 0}
      assert :new = Packer.place([other], user_demand("0xa"), 0, max_connections: 10)
    end
  end

  describe "lingering user tracking" do
    test "a removed user keeps occupying its slot for the linger window" do
      opts = [max_users_per_connection: 1, user_linger_ms: 15_000]
      demand = user_demand("0xa")

      slot =
        conn("c1")
        |> Packer.add(demand)
        |> Packer.remove(demand, false, 1_000, opts)

      # Slot still tracked 10s later ...
      refute Packer.has_headroom?(slot, user_demand("0xb"), 11_000, opts)
      assert MapSet.size(Packer.tracked_users(slot, 11_000)) == 1

      # ... and free once the window has elapsed.
      assert Packer.has_headroom?(slot, user_demand("0xb"), 17_000, opts)
      assert MapSet.size(Packer.tracked_users(slot, 17_000)) == 0
    end

    test "resubscribing the same user during the linger window reuses the slot" do
      opts = [max_users_per_connection: 1, user_linger_ms: 15_000]
      demand = user_demand("0xa")

      slot = conn("c1") |> Packer.add(demand) |> Packer.remove(demand, false, 0, opts)

      assert Packer.has_headroom?(slot, demand, 1_000, opts)
      slot = Packer.add(slot, demand)
      assert slot.lingering == %{}
    end

    test "a user with other subscriptions on the connection does not start lingering" do
      opts = [user_linger_ms: 15_000]
      demand = user_demand("0xa")

      slot =
        conn("c1")
        |> Packer.add(demand)
        |> Packer.add(demand)
        |> Packer.remove(demand, true, 0, opts)

      assert slot.lingering == %{}
      assert MapSet.member?(slot.users, "0xa")
      assert slot.subscriptions == 1
    end

    test "prune drops expired linger entries" do
      opts = [user_linger_ms: 1_000]
      demand = user_demand("0xa")

      slot =
        conn("c1")
        |> Packer.add(demand)
        |> Packer.remove(demand, false, 0, opts)
        |> Packer.prune(5_000)

      assert slot.lingering == %{}
    end
  end

  describe "group A channels (no attribution in events)" do
    test "only one group A user per connection" do
      opts = [max_users_per_connection: 15]
      slot = Packer.add(conn("c1"), user_demand("0xa", group_a?: true))

      refute Packer.has_headroom?(slot, user_demand("0xb", group_a?: true), 0, opts)
      assert Packer.has_headroom?(slot, user_demand("0xa", group_a?: true), 0, opts)
      # Group B users may still share the connection
      assert Packer.has_headroom?(slot, user_demand("0xb"), 0, opts)
    end

    test "the group A slot frees when that user leaves" do
      opts = [max_users_per_connection: 15, user_linger_ms: 0]
      demand = user_demand("0xa", group_a?: true)

      slot = conn("c1") |> Packer.add(demand) |> Packer.remove(demand, false, 0, opts)

      assert Packer.has_headroom?(slot, user_demand("0xb", group_a?: true), 1, opts)
    end
  end
end
