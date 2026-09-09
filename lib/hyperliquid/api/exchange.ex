defmodule Hyperliquid.Api.Exchange do
  @moduledoc """
  Convenience functions for Exchange API endpoints.

  This module provides snake_case wrapper functions that delegate to the
  underlying endpoint modules, improving developer ergonomics.

  ## Usage

      # Direct endpoint call (always supported)
      {:ok, result} = Hyperliquid.Api.Exchange.Order.market_open(...)

      # Convenience wrapper
      {:ok, result} = Hyperliquid.Api.Exchange.top_up_isolated_only_margin(0, 5)

  ## Note

  Most Exchange modules are hand-written action builders rather than
  `Hyperliquid.Api.ExchangeEndpoint` DSL modules, so only a subset of the
  convenience functions below are generated automatically — the rest are
  explicit delegates. Every Exchange module remains usable directly:

  - `Hyperliquid.Api.Exchange.Order`
  - `Hyperliquid.Api.Exchange.Cancel`
  - etc.

  Multi-sig wrapping of any of these actions lives in
  `Hyperliquid.Api.MultiSig`.

  See `Hyperliquid.Api.Registry.list_context_endpoints(:exchange)` for the full
  module list, and `Hyperliquid.Api.Registry.list_by_type(:exchange)` for the
  DSL-backed subset that carries metadata.
  """

  alias Hyperliquid.Api.Exchange.{
    ActivateOutcomeDeployer,
    AgentSendAsset,
    AuthorizeAqav2Role,
    FinalizeEvmContract,
    GossipPriorityBid,
    Hip3LiquidatorTransfer,
    OutcomeDeploy,
    PerpDeploy,
    SpotDeploy,
    StakingLinkDisableTradingUser,
    TopUpIsolatedOnlyMargin,
    UserOutcome
  }

  # Generate delegated functions for Exchange endpoints that use the
  # ExchangeEndpoint DSL (`__endpoint_info__/0`). Modules without the DSL are
  # skipped by the helper and covered by the explicit delegates below.
  require Hyperliquid.Api.DelegationHelper
  Hyperliquid.Api.DelegationHelper.generate_delegated_functions(:exchange)

  ## HIP-4 outcome markets — deployer actions (`outcomeDeploy`)

  @doc "Register a standalone outcome from a template. See `#{inspect(OutcomeDeploy)}`."
  defdelegate outcome_deploy_register_standalone(venue, params, opts \\ []),
    to: OutcomeDeploy,
    as: :register_standalone_outcome_from_template

  @doc "Register a question from a template. See `#{inspect(OutcomeDeploy)}`."
  defdelegate outcome_deploy_register_question(venue, params, opts \\ []),
    to: OutcomeDeploy,
    as: :register_question_from_template

  @doc "Register and associate a named outcome from a template. See `#{inspect(OutcomeDeploy)}`."
  defdelegate outcome_deploy_register_and_associate(venue, params, opts \\ []),
    to: OutcomeDeploy,
    as: :register_and_associate_named_outcome_from_template

  @doc "Settle an outcome. See `#{inspect(OutcomeDeploy)}`."
  defdelegate outcome_deploy_settle_outcome(venue, params, opts \\ []),
    to: OutcomeDeploy,
    as: :settle_outcome

  @doc "Settle a question (v2). See `#{inspect(OutcomeDeploy)}`."
  defdelegate outcome_deploy_settle_question2(venue, params, opts \\ []),
    to: OutcomeDeploy,
    as: :settle_question2

  @doc "Set the sub-deployers for a venue. See `#{inspect(OutcomeDeploy)}`."
  defdelegate outcome_deploy_set_sub_deployers(venue, sub_deployers, opts \\ []),
    to: OutcomeDeploy,
    as: :set_sub_deployers

  @doc "Activate the calling address as an outcome deployer for `venue_name`."
  defdelegate activate_outcome_deployer(venue_name, opts \\ []),
    to: ActivateOutcomeDeployer,
    as: :activate

  @doc "Deactivate the calling address as an outcome deployer."
  defdelegate deactivate_outcome_deployer(opts \\ []),
    to: ActivateOutcomeDeployer,
    as: :deactivate

  ## HIP-4 outcome markets — user actions (`userOutcome`)

  @doc "Split collateral into a full set of outcome tokens."
  defdelegate split_outcome(outcome, amount, opts \\ []), to: UserOutcome, as: :split_outcome

  @doc "Merge a full set of outcome tokens back into collateral."
  defdelegate merge_outcome(outcome, amount, opts \\ []), to: UserOutcome, as: :merge_outcome

  @doc "Merge every outcome of a question back into collateral."
  defdelegate merge_question(question, amount, opts \\ []), to: UserOutcome, as: :merge_question

  @doc "Negate an outcome within a question."
  defdelegate negate_outcome(question, outcome, amount, opts \\ []),
    to: UserOutcome,
    as: :negate_outcome

  ## Other L1 actions

  @doc "Send an asset on behalf of the account an agent is authorized for."
  defdelegate agent_send_asset(
                destination,
                source_dex,
                destination_dex,
                token,
                amount,
                opts \\ []
              ),
              to: AgentSendAsset,
              as: :request

  @doc "Authorize an AQAv2 role for a token."
  defdelegate authorize_aqav2_role(token, role, opts \\ []), to: AuthorizeAqav2Role, as: :request

  @doc "Finalize an EVM contract linked to a spot token."
  defdelegate finalize_evm_contract(token, input, opts \\ []),
    to: FinalizeEvmContract,
    as: :request

  @doc "Bid for a gossip priority slot."
  defdelegate gossip_priority_bid(slot_id, ip, max_gas, opts \\ []),
    to: GossipPriorityBid,
    as: :request

  @doc "Deposit to / withdraw from a HIP-3 dex liquidator account."
  defdelegate hip3_liquidator_transfer(dex, ntl, is_deposit, opts \\ []),
    to: Hip3LiquidatorTransfer,
    as: :request

  @doc "Top up the margin of an isolated-only position."
  defdelegate top_up_isolated_only_margin(asset, leverage, opts \\ []),
    to: TopUpIsolatedOnlyMargin,
    as: :request

  @doc "Disable trading for a linked staking user (user-signed EIP-712 action)."
  defdelegate staking_link_disable_trading_user(trading_user, opts \\ []),
    to: StakingLinkDisableTradingUser,
    as: :request

  ## HIP-3 perp deployer sub-actions

  @doc """
  `perpDeploy.setDeployerFees`.

  See `#{inspect(PerpDeploy)}` — the docs shape (`setDeployerFees`) and the
  nktkas shape (`setFeeScale` / `setGrowthModes`) both exist and have not yet
  been disambiguated against a live node.
  """
  defdelegate perp_deploy_set_deployer_fees(fees, opts \\ []),
    to: PerpDeploy,
    as: :set_deployer_fees

  @doc "`perpDeploy.setPerpAnnotation`."
  defdelegate perp_deploy_set_perp_annotation(annotation, opts \\ []),
    to: PerpDeploy,
    as: :set_perp_annotation

  @doc "`perpDeploy.disableDex`."
  defdelegate perp_deploy_disable_dex(dex, opts \\ []), to: PerpDeploy, as: :disable_dex

  ## HIP-1/2 spot deployer sub-actions

  @doc "`spotDeploy.disableQuoteToken`."
  defdelegate spot_deploy_disable_quote_token(token, opts \\ []),
    to: SpotDeploy,
    as: :disable_quote_token

  @doc "`spotDeploy.disableAlignedQuoteToken`."
  defdelegate spot_deploy_disable_aligned_quote_token(token, opts \\ []),
    to: SpotDeploy,
    as: :disable_aligned_quote_token

  @doc "`spotDeploy.setTokenAnnotation`."
  defdelegate spot_deploy_set_token_annotation(token, annotation, opts \\ []),
    to: SpotDeploy,
    as: :set_token_annotation

  @doc "`spotDeploy.setDeployerLabel`."
  defdelegate spot_deploy_set_deployer_label(label, opts \\ []),
    to: SpotDeploy,
    as: :set_deployer_label
end
