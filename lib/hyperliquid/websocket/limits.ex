defmodule Hyperliquid.WebSocket.Limits do
  @moduledoc """
  Hyperliquid WebSocket rate limits, as empirically verified.

  The published documentation is wrong about the unique-user cap. Measurements
  (see `docs/hl-api-rate-limits-and-ws-subscription-map.md` in the hypervisor
  workspace) show:

    * **15 unique users per *connection*** — not 10, and not per IP. The server
      rejects the 16th with `"Cannot track more than 15 total users."`
    * User tracking **lingers ~10-15 s after unsubscribe/disconnect**, so a slot
      is not immediately reusable.
    * ~1000 subscriptions per IP.
    * ~100 concurrent connections per IP, 30 new connections per minute.
    * ~100 inbound messages/second per IP (subscribe frames included).

  All values are configurable under the `:hyperliquid` application env:

      config :hyperliquid,
        ws_max_users_per_connection: 15,
        ws_user_linger_ms: 15_000,
        ws_max_subscriptions_per_ip: 1000,
        ws_max_connections_per_ip: 100,
        ws_max_connections_per_minute: 30,
        ws_max_messages_per_second: 50,
        ws_resubscribe_batch_size: 20

  Every value is read through `Hyperliquid.Config`, which is the single source
  of defaults. Legacy keys (`:ws_max_connections`, `:ws_max_subscriptions`) are
  still honoured when set. The old `:ws_max_users` key modelled a *global*
  budget of 10 users and has been retired.
  """

  alias Hyperliquid.Config

  @doc "Max unique user addresses tracked by a single connection (server: 15)."
  @spec max_users_per_connection() :: pos_integer()
  def max_users_per_connection do
    Config.ws_max_users_per_connection()
  end

  @doc """
  How long the server keeps tracking a user after its last subscription on a
  connection goes away. A released slot only becomes usable after this window.
  """
  @spec user_linger_ms() :: non_neg_integer()
  def user_linger_ms do
    Config.ws_user_linger_ms()
  end

  @doc "Max simultaneous subscriptions per IP."
  @spec max_subscriptions() :: pos_integer()
  def max_subscriptions do
    Config.ws_max_subscriptions_per_ip()
  end

  @doc "Max simultaneous subscriptions carried by one connection."
  @spec max_subscriptions_per_connection() :: pos_integer()
  def max_subscriptions_per_connection do
    Config.ws_max_subscriptions_per_connection()
  end

  @doc "Max simultaneous connections per IP."
  @spec max_connections() :: pos_integer()
  def max_connections do
    Config.ws_max_connections_per_ip()
  end

  @doc "Max new connections opened per minute per IP."
  @spec max_connections_per_minute() :: pos_integer()
  def max_connections_per_minute do
    Config.ws_max_connections_per_minute()
  end

  @doc "Client-side outbound message budget per second (server caps at ~100/s per IP)."
  @spec max_messages_per_second() :: pos_integer()
  def max_messages_per_second do
    Config.ws_max_messages_per_second()
  end

  @doc "How many subscribe frames a reconnecting connection replays per batch."
  @spec resubscribe_batch_size() :: pos_integer()
  def resubscribe_batch_size do
    Config.ws_resubscribe_batch_size()
  end

  @doc "Delay between resubscribe batches, derived from the message budget."
  @spec resubscribe_batch_interval_ms() :: pos_integer()
  def resubscribe_batch_interval_ms do
    max(div(resubscribe_batch_size() * 1000, max(max_messages_per_second(), 1)), 1)
  end

  @doc "Returns every limit as a map (for logging/inspection)."
  @spec all() :: map()
  def all do
    %{
      max_users_per_connection: max_users_per_connection(),
      user_linger_ms: user_linger_ms(),
      max_subscriptions: max_subscriptions(),
      max_subscriptions_per_connection: max_subscriptions_per_connection(),
      max_connections: max_connections(),
      max_connections_per_minute: max_connections_per_minute(),
      max_messages_per_second: max_messages_per_second()
    }
  end
end
