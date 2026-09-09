defmodule Hyperliquid.Api.Info.FieldGapsTest do
  @moduledoc """
  Casting tests for fields added to existing info/explorer modules to close the
  gap against `@nktkas/hyperliquid` v0.33.3. Fixtures are literals shaped like
  the HTTP transport delivers them (keys already snake_cased by
  `Hyperliquid.Transport.Http`). No network access.
  """
  use ExUnit.Case, async: true

  alias Hyperliquid.Api.Explorer.UserDetails

  alias Hyperliquid.Api.Info.{
    LegalCheck,
    MarginTable,
    SpotClearinghouseState,
    SubAccounts2,
    TwapHistory,
    UserFees,
    UserFills,
    UserFillsByTime,
    ValidatorL1Votes,
    VaultDetails
  }

  describe "marginTable dex param" do
    test "dex is omitted when not supplied" do
      assert MarginTable.build_request(0) == %{type: "marginTable", id: 0}
    end

    test "dex is appended when supplied" do
      assert MarginTable.build_request(0, dex: "test") == %{
               type: "marginTable",
               id: 0,
               dex: "test"
             }
    end

    test "dex is declared as an optional param" do
      assert MarginTable.__endpoint_info__().optional_params == [:dex]
    end
  end

  describe "userFills new fields" do
    @fill %{
      "coin" => "BTC",
      "px" => "50000.0",
      "sz" => "0.1",
      "side" => "B",
      "time" => 1_700_000_000_000,
      "start_position" => "0.0",
      "dir" => "Open Long",
      "closed_pnl" => "0.0",
      "hash" => "0x" <> String.duplicate("a", 64),
      "oid" => 123,
      "crossed" => true,
      "fee" => "1.0",
      "builder_fee" => "0.1",
      "tid" => 987,
      "fee_token" => "USDC",
      "fee_trial_escrow" => "0.5",
      "twap_id" => 42,
      "cloid" => "0x" <> String.duplicate("b", 32),
      "liquidation" => %{
        "liquidated_user" => "0x" <> String.duplicate("c", 40),
        "mark_px" => "49000.0",
        "method" => "market"
      }
    }

    test "info userFills casts builderFee/feeTrialEscrow/twapId/cloid/liquidation" do
      assert {:ok, parsed} = [@fill] |> UserFills.preprocess() |> UserFills.parse_response()
      assert [fill] = parsed.fills

      assert fill.builder_fee == "0.1"
      assert fill.fee_trial_escrow == "0.5"
      assert fill.twap_id == 42
      assert fill.cloid == "0x" <> String.duplicate("b", 32)
      assert fill.liquidation.mark_px == "49000.0"
      assert fill.liquidation.method == "market"
      assert fill.liquidation.liquidated_user == "0x" <> String.duplicate("c", 40)
    end

    test "liquidatedUser is optional (widened upstream in v0.33.3)" do
      fill = put_in(@fill, ["liquidation"], %{"mark_px" => "1.0", "method" => "backstop"})
      assert {:ok, parsed} = [fill] |> UserFills.preprocess() |> UserFills.parse_response()
      assert [%{liquidation: liquidation}] = parsed.fills
      assert liquidation.liquidated_user == nil
      assert liquidation.method == "backstop"
    end

    test "the whole optional block may be absent" do
      fill =
        Map.drop(@fill, [
          "builder_fee",
          "fee_trial_escrow",
          "twap_id",
          "cloid",
          "liquidation"
        ])

      assert {:ok, parsed} = [fill] |> UserFills.preprocess() |> UserFills.parse_response()
      assert [f] = parsed.fills
      assert f.builder_fee == nil
      assert f.twap_id == nil
      assert f.liquidation == nil
    end

    test "userFillsByTime shares the widened shape" do
      assert {:ok, parsed} =
               [@fill] |> UserFillsByTime.preprocess() |> UserFillsByTime.parse_response()

      assert [fill] = parsed.fills
      assert fill.fee_token == "USDC"
      assert fill.builder_fee == "0.1"
      assert fill.twap_id == 42
      assert fill.liquidation.method == "market"
    end
  end

  describe "spotClearinghouseState" do
    test "casts the optional ratio arrays" do
      raw = %{
        "balances" => [
          %{
            "coin" => "USDC",
            "token" => 0,
            "total" => "100.0",
            "hold" => "0.0",
            "entry_ntl" => "0.0"
          }
        ],
        "token_to_supply_ratio" => [[1, "0.5"]],
        "token_to_portfolio_supply_ratio" => [[1, "0.25"]],
        "token_to_available_after_maintenance" => [[1, "0.75"]]
      }

      assert {:ok, state} = SpotClearinghouseState.parse_response(raw)
      assert state.token_to_supply_ratio == [[1, "0.5"]]
      assert state.token_to_portfolio_supply_ratio == [[1, "0.25"]]
      assert state.token_to_available_after_maintenance == [[1, "0.75"]]
    end

    test "outcome coin prefixes: + is unsettled, o is settled" do
      assert SpotClearinghouseState.outcome_id("+12") == {:unsettled, 12}
      assert SpotClearinghouseState.outcome_id("o12") == {:settled, 12}
      assert SpotClearinghouseState.outcome_id("HYPE") == nil
      assert SpotClearinghouseState.outcome_id("@107") == nil
      assert SpotClearinghouseState.outcome_id("other") == nil
    end

    test "outcome_balances filters both prefixes" do
      balance = fn coin ->
        %{"coin" => coin, "token" => 1, "total" => "1", "hold" => "0", "entry_ntl" => "0"}
      end

      raw = %{"balances" => [balance.("USDC"), balance.("+5"), balance.("o6")]}
      assert {:ok, state} = SpotClearinghouseState.parse_response(raw)
      assert Enum.map(SpotClearinghouseState.outcome_balances(state), & &1.coin) == ["+5", "o6"]
    end
  end

  describe "subAccounts2 abstraction" do
    test "casts the abstraction mode when present" do
      raw = [
        %{
          "sub_account_user" => "0x" <> String.duplicate("1", 40),
          "name" => "sub",
          "master" => "0x" <> String.duplicate("2", 40),
          "abstraction" => "portfolioMargin"
        }
      ]

      assert {:ok, parsed} = raw |> SubAccounts2.preprocess() |> SubAccounts2.parse_response()
      assert [account] = parsed.accounts
      assert account.abstraction == "portfolioMargin"
    end

    test "abstraction is absent on default-mode accounts" do
      raw = [
        %{
          "sub_account_user" => "0x" <> String.duplicate("1", 40),
          "name" => "sub",
          "master" => "0x" <> String.duplicate("2", 40)
        }
      ]

      assert {:ok, parsed} = raw |> SubAccounts2.preprocess() |> SubAccounts2.parse_response()
      assert [%{abstraction: nil}] = parsed.accounts
    end
  end

  describe "legalCheck restrictions" do
    test "casts the restriction code" do
      raw = %{
        "ip_allowed" => true,
        "accepted_terms" => true,
        "user_allowed" => true,
        "restrictions" => "o"
      }

      assert {:ok, check} = LegalCheck.parse_response(raw)
      assert check.restrictions == "o"
      assert LegalCheck.restriction_description("o") == "outcome markets hidden"
      assert LegalCheck.outcome_markets_hidden?(check)
      refute LegalCheck.unrestricted?(check)
    end

    test "all four documented codes are known" do
      assert Map.keys(LegalCheck.restrictions()) |> Enum.sort() == ["a", "n", "o", "u"]
    end

    test "still casts when restrictions is absent" do
      raw = %{"ip_allowed" => true, "accepted_terms" => true, "user_allowed" => true}
      assert {:ok, check} = LegalCheck.parse_response(raw)
      assert LegalCheck.unrestricted?(check)
    end
  end

  describe "userFees stakingLink union" do
    test "stakingUser variant carries trading_user, not staking_user" do
      fees = %UserFees{
        user_cross_rate: "0.0004",
        user_add_rate: "0.0001",
        staking_link: %{"type" => "stakingUser", "trading_user" => "0xabc"}
      }

      assert UserFees.staking_link_counterparty(fees) == {"stakingUser", "0xabc"}
    end

    test "requested/tradingUser variants carry staking_user" do
      fees = %UserFees{staking_link: %{"type" => "requested", "staking_user" => "0xdef"}}
      assert UserFees.staking_link_counterparty(fees) == {"requested", "0xdef"}
    end

    test "nil link" do
      assert UserFees.staking_link_counterparty(%UserFees{staking_link: nil}) == nil
    end
  end

  describe "vaultDetails nullable response" do
    test "a null response parses to {:ok, nil} instead of failing the changeset" do
      assert {:ok, nil} = nil |> VaultDetails.preprocess() |> VaultDetails.parse_response()
    end

    test "a real vault still casts" do
      raw = %{
        "name" => "Test Vault",
        "vault_address" => "0x" <> String.duplicate("1", 40),
        "leader" => "0x" <> String.duplicate("2", 40),
        "description" => "",
        "portfolio" => [],
        "apr" => 0.1,
        "followers" => [],
        "is_closed" => false,
        "allow_deposits" => true
      }

      assert {:ok, details} = VaultDetails.parse_response(raw)
      assert details.name == "Test Vault"
      assert VaultDetails.deposits_allowed?(details)
    end
  end

  describe "validatorL1Votes structured votes" do
    test "string votes keep working" do
      raw = [%{"validator" => "0xabc", "vote" => "yes", "time" => 1}]

      assert {:ok, parsed} =
               raw |> ValidatorL1Votes.preprocess() |> ValidatorL1Votes.parse_response()

      assert [vote] = parsed.votes
      assert vote.vote == "yes"
      assert vote.vote_data == nil
      assert ValidatorL1Votes.vote_payload(vote) == nil
    end

    test "HIP-4 object votes keep both the variant name and the payload" do
      payload = %{
        "question" => 3,
        "outcome_settlements" => [
          %{
            "outcome" => 95,
            "settle_fraction" => "1",
            "details" => "",
            "name_and_description" => ["n", "d"],
            "side_names" => ["Yes", "No"]
          }
        ],
        "name_and_description" => ["n", "d"]
      }

      raw = [
        %{
          "validator" => "0xabc",
          "vote" => %{"settle_question2" => payload},
          "time" => 1
        }
      ]

      assert {:ok, parsed} =
               raw |> ValidatorL1Votes.preprocess() |> ValidatorL1Votes.parse_response()

      assert [vote] = parsed.votes
      assert vote.vote == "settle_question2"
      assert ValidatorL1Votes.vote_payload(vote) == payload
      assert [^vote] = ValidatorL1Votes.by_variant(parsed, "settle_question2")
    end
  end

  describe "twapHistory trigger/stop price and statuses" do
    @record %{
      "time" => 1_700_000_000_000,
      "twap_id" => 7,
      "state" => %{
        "coin" => "BTC",
        "executed_ntl" => "0.0",
        "executed_sz" => "0.0",
        "minutes" => 30,
        "randomize" => false,
        "reduce_only" => false,
        "side" => "B",
        "sz" => "1.0",
        "timestamp" => 1_700_000_000_000,
        "user" => "0x" <> String.duplicate("1", 40),
        "stop_px" => "45000.0",
        "trigger" => %{"px" => "51000.0", "above" => true}
      },
      "status" => %{"status" => "waitingForTrigger", "description" => ""}
    }

    test "casts stop_px and trigger" do
      assert {:ok, parsed} = [@record] |> TwapHistory.preprocess() |> TwapHistory.parse_response()
      assert [record] = parsed.records
      assert record.state.stop_px == "45000.0"
      assert record.state.trigger == %{"px" => "51000.0", "above" => true}
    end

    test "nil trigger and stop price" do
      record = put_in(@record, ["state", "trigger"], nil)
      record = put_in(record, ["state", "stop_px"], nil)
      assert {:ok, parsed} = [record] |> TwapHistory.preprocess() |> TwapHistory.parse_response()
      assert [%{state: %{trigger: nil, stop_px: nil}}] = parsed.records
    end

    test "waitingForTrigger is pending but not active" do
      assert {:ok, parsed} = [@record] |> TwapHistory.preprocess() |> TwapHistory.parse_response()
      assert TwapHistory.active(parsed) == []
      assert [_] = TwapHistory.waiting_for_trigger(parsed)
      assert [_] = TwapHistory.pending(parsed)
    end

    test "the two new statuses are listed" do
      assert "waitingForTrigger" in TwapHistory.valid_statuses()
      assert "stopped" in TwapHistory.valid_statuses()
    end
  end

  describe "explorer userDetails positional action" do
    test "tolerates a tx whose action is a list" do
      raw = %{
        "txs" => [
          %{"time" => 1, "user" => "0xabc", "action" => %{"type" => "order"}, "hash" => "0x1"},
          %{"time" => 2, "user" => "0xabc", "action" => [0, "order", 1], "hash" => "0x2"}
        ]
      }

      assert {:ok, details} = raw |> UserDetails.preprocess() |> UserDetails.parse_response()
      assert UserDetails.tx_count(details) == 2

      [object_tx, positional_tx] = details.txs
      refute UserDetails.positional_action?(object_tx)
      assert UserDetails.positional_action?(positional_tx)
      assert UserDetails.action(positional_tx) == [0, "order", 1]
    end

    test "non-map tx entries are dropped rather than failing the cast" do
      raw = %{"txs" => [%{"time" => 1, "action" => []}, "garbage"]}
      assert {:ok, details} = raw |> UserDetails.preprocess() |> UserDetails.parse_response()
      assert UserDetails.tx_count(details) == 1
    end
  end
end
