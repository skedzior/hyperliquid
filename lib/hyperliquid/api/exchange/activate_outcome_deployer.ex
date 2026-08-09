defmodule Hyperliquid.Api.Exchange.ActivateOutcomeDeployer do
  @moduledoc """
  Activate or deactivate an account as a HIP-4 outcome deployer.

  Activation claims a venue name: 2-4 lowercase ASCII letters, subject to the
  same rules as HIP-3 perp DEX names. The name must be unique across the venue
  names of all deployers — including deactivated ones, whose names stay reserved
  — and must not collide with an existing perp DEX name (nor `spot`).

  Active deployers must maintain the deployer staking requirement, which stacks
  with any other staking requirements the account has. Deactivation requires that
  the minimum deployer staking duration (183 days, restarted on re-activation)
  has elapsed and that the deployer has no active outcomes.

  Deployers must use Standard account abstraction.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/hip-4-deployer-actions

  > #### Wire format {: .warning}
  >
  > The docs page carries two different shapes for this action. The action
  > format block specifies `{"activate": {"venueName": ...}}` and
  > `{"deactivate": null}`, which is what this module sends. A later sentence on
  > the same page instead says to deactivate with `"isDeactivate": true`, and the
  > nktkas TypeScript SDK implements that older boolean form with no venue name
  > at all. The `activate`/`deactivate` form is the newer of the two: it is the
  > only one that can carry a venue name, and venue names are specified at length
  > on the same page.
  """

  alias Hyperliquid.{Config, Signer}
  alias Hyperliquid.Transport.Http

  @venue_name_format ~r/^[a-z]{2,4}$/

  @doc """
  Activate the signing account as an outcome deployer under `venue_name`.

  ## Parameters
    - `venue_name`: 2-4 lowercase ASCII letters, unique across all venue names
    - `opts`: Optional parameters

  ## Options
    - `:private_key` - Private key for signing (falls back to config)
    - `:vault_address` - Act on behalf of a vault

  ## Returns
    - `{:ok, response}` - Activation result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = ActivateOutcomeDeployer.activate("abcd")
  """
  @spec activate(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def activate(venue_name, opts \\ []) when is_binary(venue_name) do
    unless Regex.match?(@venue_name_format, venue_name) do
      raise ArgumentError,
            "venue name must be 2-4 lowercase ASCII letters, got: #{inspect(venue_name)}"
    end

    request(%{activate: %{venueName: venue_name}}, opts)
  end

  @doc """
  Deactivate the signing account as an outcome deployer.

  Requires that the minimum deployer staking duration has elapsed and that the
  deployer has no active outcomes. The venue name stays reserved.

  ## Parameters
    - `opts`: Optional parameters

  ## Returns
    - `{:ok, response}` - Deactivation result
    - `{:error, term()}` - Error details

  ## Examples

      {:ok, result} = ActivateOutcomeDeployer.deactivate()
  """
  @spec deactivate(keyword()) :: {:ok, map()} | {:error, term()}
  def deactivate(opts \\ []) do
    request(%{deactivate: nil}, opts)
  end

  defp request(variant, opts) do
    private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = Map.merge(%{type: "activateOutcomeDeployer"}, variant)

    with {:ok, action_json} <- Hyperliquid.Api.ActionEncoder.encode(action),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after) do
      Http.exchange_request(action, signature, nonce, vault_address, expires_after, opts)
    end
  end

  defp sign_action(private_key, action_json, nonce, vault_address, expires_after) do
    is_mainnet = Config.mainnet?()

    connection_id =
      Signer.compute_connection_id_ex(action_json, nonce, vault_address, expires_after)

    case Signer.sign_l1_action(private_key, connection_id, is_mainnet) do
      %{"r" => r, "s" => s, "v" => v} -> {:ok, %{r: r, s: s, v: v}}
      error -> {:error, {:signing_error, error}}
    end
  end

  defp generate_nonce do
    System.system_time(:millisecond)
  end
end
