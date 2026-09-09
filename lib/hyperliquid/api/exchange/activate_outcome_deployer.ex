defmodule Hyperliquid.Api.Exchange.ActivateOutcomeDeployer do
  @moduledoc """
  Activate or deactivate the calling address as a HIP-4 outcome-market deployer.

  L1-signed.

      {"type": "activateOutcomeDeployer", "activate": {"venueName": "<2-4 lowercase letters>"}}
      {"type": "activateOutcomeDeployer", "deactivate": null}

  ## Constraints
    - Activation requires a `venueName` that is unique across all deployers.
    - Deactivation requires a staking duration of at least 183 days and zero active outcomes.

  ## Shape note

  `@nktkas/hyperliquid` v0.33.3 emits a flatter `{"type":"activateOutcomeDeployer",
  "isDeactivate": bool}` shape with no venue name. This module follows the official
  HIP-4 deployer-actions page (`activate` / `deactivate` variants), which is newer and
  carries the venue name that `outcomeDeploy` requires.

  See: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/hip-4-deployer-actions
  """

  alias Hyperliquid.Config
  alias Hyperliquid.Api.Exchange.KeyUtils
  alias Hyperliquid.Transport.Http

  @venue_regex ~r/^[a-z]{2,4}$/

  @doc """
  Activate the calling address as an outcome deployer under `venue_name`.

  ## Parameters
    - `venue_name`: Venue name (2–4 lowercase ASCII letters), unique across all deployers
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def activate(venue_name, opts \\ []) do
    unless is_binary(venue_name) and Regex.match?(@venue_regex, venue_name) do
      raise ArgumentError,
            "venue_name must be 2-4 lowercase ASCII letters, got #{inspect(venue_name)}"
    end

    build_action({:activate, venue_name})
    |> send_action(opts)
  end

  @doc """
  Deactivate the calling address as an outcome deployer.

  Requires >= 183 days of staking duration and zero active outcomes.

  ## Parameters
    - `opts`: Optional keyword list (`:private_key`, `:vault_address`)
  """
  def deactivate(opts \\ []) do
    build_action(:deactivate)
    |> send_action(opts)
  end

  @doc false
  # Exposed for tests: builds the signed action without performing IO.
  def build_action({:activate, venue_name}) do
    Jason.OrderedObject.new([
      {:type, "activateOutcomeDeployer"},
      {:activate, Jason.OrderedObject.new([{:venueName, venue_name}])}
    ])
  end

  def build_action(:deactivate) do
    Jason.OrderedObject.new([
      {:type, "activateOutcomeDeployer"},
      {:deactivate, nil}
    ])
  end

  # ===================== Transport =====================

  defp send_action(action, opts) do
    private_key = KeyUtils.resolve_private_key!(opts)
    vault_address = Keyword.get(opts, :vault_address)
    nonce = generate_nonce()
    expires_after = Config.expires_after()

    action = Hyperliquid.Api.Exchange.Action.ordered(action)

    with {:ok, action_json} <- Jason.encode(action),
         {:ok, signature} <-
           sign_action(private_key, action_json, nonce, vault_address, expires_after) do
      Http.exchange_request(action, signature, nonce, vault_address, expires_after, opts)
    end
  end

  defp sign_action(private_key, action_json, nonce, vault_address, expires_after) do
    Hyperliquid.Api.Exchange.Action.sign_json(
      private_key,
      action_json,
      nonce,
      vault_address,
      expires_after
    )
  end

  defp generate_nonce, do: Hyperliquid.Utils.generate_nonce()
end
