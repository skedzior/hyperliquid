defmodule Hyperliquid.Api.Explorer.UserDetails do
  @moduledoc """
  User transaction history from the explorer.

  Returns recent transactions for a user address.

  ## `action` may be a positional list

  As of `@nktkas/hyperliquid` v0.33.3 `txs[].action` is typed
  `ExplorerTransaction["action"] | unknown[]` - historical entries can be a
  positional **array** rather than an object. `txs` is stored as
  `{:array, :map}`, so the tx envelope must stay a map but its nested `action`
  may be a list; `action/1` normalises both forms and
  `positional_action?/1` tells them apart.

  `preprocess/1` additionally drops any non-map tx entry rather than failing the
  whole cast.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/explorer

  ## Usage

      {:ok, details} = UserDetails.request("0x1234...")
      UserDetails.tx_count(details)
  """

  use Hyperliquid.Api.Endpoint,
    type: :explorer,
    request_type: "userDetails",
    params: [:user],
    rate_limit_cost: 2,
    doc: "Retrieve user transaction history",
    returns: "List of recent transactions for the user"

  @type tx :: %{
          time: non_neg_integer(),
          user: String.t(),
          action: map() | list(),
          grouping: String.t()
        }

  @type t :: %__MODULE__{
          txs: [tx()]
        }

  @primary_key false
  embedded_schema do
    field(:txs, {:array, :map})
  end

  # ===================== Preprocessing =====================

  @doc false
  def preprocess(%{"txs" => txs} = data) when is_list(txs) do
    Map.put(data, "txs", Enum.filter(txs, &is_map/1))
  end

  def preprocess(%{txs: txs} = data) when is_list(txs) do
    Map.put(data, :txs, Enum.filter(txs, &is_map/1))
  end

  def preprocess(data) when is_list(data), do: %{txs: Enum.filter(data, &is_map/1)}
  def preprocess(nil), do: %{txs: []}
  def preprocess(data), do: data

  # ===================== Changesets =====================

  @doc """
  Creates a changeset for user details data.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(details \\ %__MODULE__{}, attrs) do
    details
    |> cast(attrs, [:txs])
  end

  # ===================== Helpers =====================

  @doc """
  Return a transaction's action, which is either a map or a positional list.
  """
  @spec action(map()) :: map() | list() | nil
  def action(tx) when is_map(tx), do: Map.get(tx, "action") || Map.get(tx, :action)
  def action(_), do: nil

  @doc """
  True when a transaction's action is the legacy positional list form.
  """
  @spec positional_action?(map()) :: boolean()
  def positional_action?(tx), do: is_list(action(tx))

  @doc """
  Get the number of transactions.
  """
  @spec tx_count(t()) :: non_neg_integer()
  def tx_count(%__MODULE__{txs: txs}) when is_list(txs), do: length(txs)
  def tx_count(_), do: 0

  @doc """
  Get the most recent transaction.
  """
  @spec latest_tx(t()) :: {:ok, tx()} | {:error, :no_transactions}
  def latest_tx(%__MODULE__{txs: [tx | _]}), do: {:ok, tx}
  def latest_tx(_), do: {:error, :no_transactions}
end
