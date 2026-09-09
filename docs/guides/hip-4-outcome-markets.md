# HIP-4 Outcome Markets

HIP-4 outcome markets are deployed and settled through the top-level
`outcomeDeploy` action, and traded/redeemed through `userOutcome`.

## Reading

| Module | Description |
|--------|-------------|
| `Hyperliquid.Api.Info.OutcomeTemplates` | Templates available to deployers |
| `Hyperliquid.Api.Info.OutcomeMeta` | Metadata for deployed outcome markets |
| `Hyperliquid.Api.Info.SettledOutcome` | Settlement result (`{:ok, nil}` while unsettled) |
| `Hyperliquid.Api.Info.OutcomeDeployerLimits` | Deployer limits (untyped passthrough) |
| `Hyperliquid.Api.Subscription.OutcomeMetaUpdates` | Live metadata updates |

Settled-outcome balances appear in `spotClearinghouseState` under coins with the
`"oN"` prefix; `SpotClearinghouseState.outcome_id/1` parses them.

## Deploying — `Hyperliquid.Api.Exchange.OutcomeDeploy`

`outcomeDeploy` is a **top-level action with a required top-level `venue`**, per
the official HIP-4 page. The nested `spotDeploy.outcome` variant that
`@nktkas/hyperliquid` still emits is deliberately not implemented.

| Function | Operation |
|----------|-----------|
| `register_standalone_outcome_from_template/3` | `registerStandaloneOutcomeFromTemplate` |
| `register_question_from_template/3` | `registerQuestionFromTemplate` |
| `register_and_associate_named_outcome_from_template/3` | `registerAndAssociateNamedOutcomeFromTemplate` |
| `settle_outcome/3` | `settleOutcome` |
| `settle_question2/3` | `settleQuestion2` |
| `set_sub_deployers/3` | `setSubDeployers` (payload is a bare list, not an object) |

Convenience delegates exist on `Hyperliquid.Api.Exchange` as
`outcome_deploy_register_standalone/3`, `outcome_deploy_settle_outcome/3`, etc.

### Constraints

- `keywordToValue` must be **sorted by key**.
- `details` must be `""` when unused - not `nil`, not omitted.
- `deployerFeeScale` must be in `[0, 10]`.
- `settleFraction` must be in `[0, 1]`.
- Sub-deployer `variant` values are validated against the five documented
  variants.

## Activation — `Hyperliquid.Api.Exchange.ActivateOutcomeDeployer`

```elixir
Hyperliquid.Api.Exchange.activate_outcome_deployer("my-venue")
Hyperliquid.Api.Exchange.deactivate_outcome_deployer()
```

This implements the **official docs shape**
(`{"activate": {"venueName": ...}}` / `{"deactivate": null}`) rather than the
nktkas shape (`{"isDeactivate": bool}`), because it is newer and carries the
venue name that `outcomeDeploy` needs. Flagged in the module's moduledoc.

## Trading — `Hyperliquid.Api.Exchange.UserOutcome`

```elixir
Hyperliquid.Api.Exchange.split_outcome(outcome_id, amount)
Hyperliquid.Api.Exchange.merge_outcome(outcome_id, amount)
Hyperliquid.Api.Exchange.merge_question(question_id, amount)
Hyperliquid.Api.Exchange.negate_outcome(question_id, outcome_id, amount)
```

## Order Notes

- The minimum notional on an outcome order is **$1**, not the $10 that applies
  to perps and spot.
- Builder fees on outcome buys are charged in the **quote token**.
