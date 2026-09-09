defmodule Hyperliquid.WebSocket.Packer do
  @moduledoc """
  Pure bin-packing of subscriptions onto WebSocket connections.

  Hyperliquid's unique-user cap is **per connection** (15), not global, so the
  right strategy is to pack new subscriptions onto an existing connection that
  still has headroom and to open a new connection only when every existing one
  is full. Packing 15 users per connection instead of one gives ~15x the
  capacity for the same connection budget.

  A connection slot is a plain map:

      %{
        key: "conn:1",
        url: "wss://api.hyperliquid.xyz/ws",
        subscriptions: 12,
        users: MapSet.new(["0xabc"]),
        # user => monotonic-ish ms timestamp at which the server is expected to
        # have released the tracking slot
        lingering: %{"0xdef" => 1_723_000_000_000},
        group_a_users: MapSet.new()
      }

  Users that were just released still occupy a slot until their linger window
  expires (`Limits.user_linger_ms/0`), which is what the server actually does.

  Group A channels (`orderUpdates`, `userEvents`, `notification`) carry no user
  attribution in their events, so at most one Group A user may live on a
  connection; anything else would be undemultiplexable cross-user bleed.

  All functions are pure — no process state, no I/O — which makes the packing
  math directly testable.
  """

  alias Hyperliquid.WebSocket.Limits

  @type conn :: %{
          required(:key) => String.t(),
          required(:url) => String.t(),
          required(:subscriptions) => non_neg_integer(),
          required(:users) => MapSet.t(),
          required(:lingering) => %{optional(String.t()) => integer()},
          required(:group_a_users) => MapSet.t()
        }

  @type demand :: %{
          required(:url) => String.t(),
          optional(:user) => String.t() | nil,
          optional(:group_a?) => boolean()
        }

  @doc "A fresh, empty connection slot."
  @spec new_connection(String.t(), String.t()) :: conn()
  def new_connection(key, url) do
    %{
      key: key,
      url: url,
      subscriptions: 0,
      users: MapSet.new(),
      lingering: %{},
      group_a_users: MapSet.new()
    }
  end

  @doc """
  Choose a connection for `demand`.

  Returns:

    * `{:ok, key}` — pack onto this existing connection
    * `:new` — no existing connection has headroom, open one (the caller still
      has to check the connection budget)
    * `{:error, :connection_limit_exceeded}` — no headroom and no budget left
  """
  @spec place([conn()], demand(), integer(), keyword()) ::
          {:ok, String.t()} | :new | {:error, :connection_limit_exceeded}
  def place(connections, demand, now, opts \\ []) do
    max_connections = Keyword.get(opts, :max_connections, Limits.max_connections())

    candidates =
      connections
      |> Enum.filter(&(&1.url == demand.url))
      |> Enum.filter(&has_headroom?(&1, demand, now, opts))

    case best_fit(candidates, demand, now) do
      nil ->
        if length(connections) < max_connections do
          :new
        else
          {:error, :connection_limit_exceeded}
        end

      conn ->
        {:ok, conn.key}
    end
  end

  @doc """
  True when `conn` can accept `demand` without breaching a per-connection cap.
  """
  @spec has_headroom?(conn(), demand(), integer(), keyword()) :: boolean()
  def has_headroom?(conn, demand, now, opts \\ []) do
    max_users = Keyword.get(opts, :max_users_per_connection, Limits.max_users_per_connection())

    max_subs =
      Keyword.get(
        opts,
        :max_subscriptions_per_connection,
        Limits.max_subscriptions_per_connection()
      )

    user = Map.get(demand, :user)
    group_a? = Map.get(demand, :group_a?, false)

    sub_room? = conn.subscriptions < max_subs

    user_room? =
      cond do
        is_nil(user) -> true
        user in tracked_users(conn, now) -> true
        MapSet.size(tracked_users(conn, now)) < max_users -> true
        true -> false
      end

    group_a_room? =
      cond do
        not group_a? -> true
        MapSet.size(conn.group_a_users) == 0 -> true
        MapSet.member?(conn.group_a_users, user) -> true
        true -> false
      end

    sub_room? and user_room? and group_a_room?
  end

  @doc """
  Every user currently counting against `conn`'s cap: active users plus users
  whose server-side tracking has not yet lapsed.
  """
  @spec tracked_users(conn(), integer()) :: MapSet.t()
  def tracked_users(conn, now) do
    lingering =
      conn.lingering
      |> Enum.filter(fn {_user, expires_at} -> expires_at > now end)
      |> Enum.map(fn {user, _} -> user end)
      |> MapSet.new()

    MapSet.union(conn.users, lingering)
  end

  @doc "Free capacity (in unique users) on `conn`."
  @spec headroom(conn(), integer(), keyword()) :: integer()
  def headroom(conn, now, opts \\ []) do
    max_users = Keyword.get(opts, :max_users_per_connection, Limits.max_users_per_connection())
    max_users - MapSet.size(tracked_users(conn, now))
  end

  @doc "Record a subscription placed on `conn`."
  @spec add(conn(), demand()) :: conn()
  def add(conn, demand) do
    user = Map.get(demand, :user)
    group_a? = Map.get(demand, :group_a?, false)

    conn
    |> Map.update!(:subscriptions, &(&1 + 1))
    |> then(fn c -> if user, do: Map.update!(c, :users, &MapSet.put(&1, user)), else: c end)
    |> then(fn c ->
      if user, do: Map.update!(c, :lingering, &Map.delete(&1, user)), else: c
    end)
    |> then(fn c ->
      if group_a? and user,
        do: Map.update!(c, :group_a_users, &MapSet.put(&1, user)),
        else: c
    end)
  end

  @doc """
  Record a subscription removed from `conn`.

  `still_present?` says whether the user still has other subscriptions on this
  connection; when it does not, the user moves into the lingering set for
  `Limits.user_linger_ms/0` rather than freeing its slot immediately.
  """
  @spec remove(conn(), demand(), boolean(), integer(), keyword()) :: conn()
  def remove(conn, demand, still_present?, now, opts \\ []) do
    linger = Keyword.get(opts, :user_linger_ms, Limits.user_linger_ms())
    user = Map.get(demand, :user)
    group_a? = Map.get(demand, :group_a?, false)

    conn = Map.update!(conn, :subscriptions, &max(&1 - 1, 0))

    cond do
      is_nil(user) ->
        conn

      still_present? ->
        conn

      true ->
        conn
        |> Map.update!(:users, &MapSet.delete(&1, user))
        |> Map.update!(:lingering, &Map.put(&1, user, now + linger))
        |> then(fn c ->
          if group_a?, do: Map.update!(c, :group_a_users, &MapSet.delete(&1, user)), else: c
        end)
    end
  end

  @doc "Drop expired linger entries."
  @spec prune(conn(), integer()) :: conn()
  def prune(conn, now) do
    Map.update!(conn, :lingering, fn lingering ->
      lingering
      |> Enum.filter(fn {_user, expires_at} -> expires_at > now end)
      |> Map.new()
    end)
  end

  # Best fit: prefer a connection that already tracks this user (free), then the
  # fullest connection that still has room, so connections stay dense and new
  # ones are opened as rarely as possible. Ties break on key for determinism.
  defp best_fit([], _demand, _now), do: nil

  defp best_fit(candidates, demand, now) do
    user = Map.get(demand, :user)

    Enum.min_by(candidates, fn conn ->
      already? = user != nil and MapSet.member?(tracked_users(conn, now), user)
      {if(already?, do: 0, else: 1), -MapSet.size(tracked_users(conn, now)), conn.key}
    end)
  end
end
