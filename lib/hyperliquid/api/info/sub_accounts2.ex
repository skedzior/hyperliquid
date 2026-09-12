defmodule Hyperliquid.Api.Info.SubAccounts2 do
  @moduledoc """
  Extended sub-accounts information.

  Returns sub-accounts with additional details like balances.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint

  ## Usage

      {:ok, accounts} = SubAccounts2.request("0x...")
      SubAccounts2.count(accounts)
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "subAccounts2",
    params: [:user],
    rate_limit_cost: 1,
    doc: "Retrieve extended sub-accounts information",
    returns: "Sub-accounts with additional details like balances"

  @type t :: %__MODULE__{
          accounts: [Account.t()]
        }

  @primary_key false
  embedded_schema do
    embeds_many :accounts, Account, primary_key: false do
      @moduledoc "Extended sub-account info."

      field(:sub_account_user, :string)
      field(:name, :string)
      field(:master, :string)
      field(:clearinghouse_state, :map)
      field(:spot_state, :map)

      # Account abstraction mode; absent from the payload when the sub-account
      # is on the default mode.
      # One of "unifiedAccount" | "portfolioMargin" | "disabled".
      # (The former "dexAbstraction" value was removed upstream in v0.33.3 -
      # DEX abstraction is now its own boolean flag.)
      field(:abstraction, :string)
    end
  end

  # ===================== Preprocessing =====================

  @doc false
  # The API returns `null` (not `[]`) for a user with no sub-accounts.
  def preprocess(nil), do: %{accounts: []}

  def preprocess(data) when is_list(data) do
    %{accounts: data}
  end

  def preprocess(data), do: data

  # ===================== Changesets =====================

  @doc """
  Creates a changeset for sub accounts 2 data.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(accounts \\ %__MODULE__{}, attrs) do
    accounts
    |> cast(attrs, [])
    |> cast_embed(:accounts, with: &account_changeset/2)
  end

  defp account_changeset(account, attrs) do
    account
    |> cast(attrs, [
      :sub_account_user,
      :name,
      :master,
      :clearinghouse_state,
      :spot_state,
      :abstraction
    ])
    |> validate_required([:sub_account_user, :name, :master])
  end

  # ===================== Helpers =====================

  @doc """
  Get count.
  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{accounts: accounts}), do: length(accounts)
end
