defmodule Hyperliquid.Api.Info.SubAccounts do
  @moduledoc """
  User's sub-accounts.

  Returns list of sub-accounts for a user.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint#retrieve-a-users-sub-accounts

  ## Usage

      {:ok, accounts} = SubAccounts.request("0x...")
      {:ok, account} = SubAccounts.find_by_name(accounts, "Trading")
  """

  use Hyperliquid.Api.Endpoint,
    type: :info,
    request_type: "subAccounts",
    params: [:user],
    rate_limit_cost: 1,
    doc: "Retrieve user's sub-accounts",
    returns: "List of sub-accounts for a user"

  @type t :: %__MODULE__{
          accounts: [Account.t()]
        }

  @primary_key false
  embedded_schema do
    embeds_many :accounts, Account, primary_key: false do
      @moduledoc "Sub-account."

      field(:sub_account_user, :string)
      field(:name, :string)
      field(:master, :string)
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
  Creates a changeset for sub accounts data.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(accounts \\ %__MODULE__{}, attrs) do
    accounts
    |> cast(attrs, [])
    |> cast_embed(:accounts, with: &account_changeset/2)
  end

  defp account_changeset(account, attrs) do
    account
    |> cast(attrs, [:sub_account_user, :name, :master])
    |> validate_required([:sub_account_user, :name, :master])
  end

  # ===================== Helpers =====================

  @doc """
  Find by name.
  """
  @spec find_by_name(t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def find_by_name(%__MODULE__{accounts: accounts}, name) do
    case Enum.find(accounts, &(&1.name == name)) do
      nil -> {:error, :not_found}
      account -> {:ok, account}
    end
  end

  @doc """
  Get count.
  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{accounts: accounts}), do: length(accounts)

  @doc """
  Get all addresses.
  """
  @spec addresses(t()) :: [String.t()]
  def addresses(%__MODULE__{accounts: accounts}) do
    Enum.map(accounts, & &1.sub_account_user)
  end
end
