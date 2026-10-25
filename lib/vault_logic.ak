use aiken/collection/list
use aiken/crypto.{ScriptHash, VerificationKeyHash}
use auth.{signed_by}
use cardano/address.{VerificationKey, from_verification_key}
use cardano/assets.{Assets, PolicyId, from_asset, quantity_of, zero}
use cardano/transaction.{
  Input, NoDatum, Output, OutputReference, Spend, Transaction,
}
use constants.{
  junior_share_asset_name, senior_share_asset_name, whitelist_asset_name,
}
use credit_logic.{
  expected_open_loan, exposure_from_reference_inputs, usdcx_paid_to_borrower,
  validate_loan_output, vault_tvl, within_concentration_limit,
}
use repay_logic.{validate_vault_repay}
use shares.{assets_for_withdraw, shares_for_deposit}
use types.{
  Deposit, Disburse, Junior, RecordRepayment, Senior, Tranche, UpdateConfig,
  VaultConfig, VaultDatum, VaultRedeemer, Withdraw, tranche_assets,
  tranche_shares, with_tranche_assets, with_tranche_shares,
}

/// Depositor input holds at least one KYC token from the whitelist policy.
pub fn has_whitelist_token(
  inputs: List<Input>,
  depositor: VerificationKeyHash,
  whitelist_policy: PolicyId,
) -> Bool {
  list.any(
    inputs,
    fn(input) {
      when input.output.address.payment_credential is {
        VerificationKey(vkh) ->
          if vkh == depositor {
            quantity_of(
              input.output.value,
              whitelist_policy,
              whitelist_asset_name(),
            ) >= 1
          } else {
            False
          }
        _ -> False
      }
    },
  )
}

pub fn deposit_authorized(
  tranche: Tranche,
  depositor: VerificationKeyHash,
  curator: VerificationKeyHash,
  extra: List<VerificationKeyHash>,
  inputs: List<Input>,
  whitelist_policy: PolicyId,
) -> Bool {
  when tranche is {
    Senior -> has_whitelist_token(inputs, depositor, whitelist_policy)
    Junior -> signed_by(extra, curator)
  }
}

pub fn apply_deposit(
  datum: VaultDatum,
  tranche: Tranche,
  deposit: Int,
) -> Option<(VaultDatum, Int)> {
  let total_assets = tranche_assets(datum, tranche)
  let total_shares = tranche_shares(datum, tranche)
  when shares_for_deposit(deposit, total_assets, total_shares) is {
    None -> None
    Some(minted) -> {
      let next = datum
        |> with_tranche_assets(tranche, total_assets + deposit)
        |> with_tranche_shares(tranche, total_shares + minted)
      Some((next, minted))
    }
  }
}

pub fn apply_withdraw(
  datum: VaultDatum,
  tranche: Tranche,
  shares_burned: Int,
) -> Option<(VaultDatum, Int)> {
  let total_assets = tranche_assets(datum, tranche)
  let total_shares = tranche_shares(datum, tranche)
  when assets_for_withdraw(shares_burned, total_assets, total_shares) is {
    None -> None
    Some(payout) -> {
      let next = datum
        |> with_tranche_assets(tranche, total_assets - payout)
        |> with_tranche_shares(tranche, total_shares - shares_burned)
      Some((next, payout))
    }
  }
}

pub fn apply_config_update(datum: VaultDatum, config: VaultConfig) -> VaultDatum {
  VaultDatum { ..datum, config }
}

pub fn apply_disburse(datum: VaultDatum, principal: Int) -> Option<VaultDatum> {
  if principal <= 0 {
    None
  } else {
    Some(
      VaultDatum {
        ..datum,
        deployed_outstanding: datum.deployed_outstanding + principal,
      },
    )
  }
}

/// Validates vault datum transition and USDCx delta for deposit / withdraw / config.
pub fn validate_vault_spend(
  vault_script: ScriptHash,
  input_datum: VaultDatum,
  output_datum: VaultDatum,
  redeemer: VaultRedeemer,
  input_usdcx: Int,
  output_usdcx: Int,
  extra: List<VerificationKeyHash>,
  inputs: List<Input>,
  reference_inputs: List<Input>,
  outputs: List<Output>,
) -> Bool {
  when redeemer is {
    Deposit { tranche, depositor } -> {
      let deposit = output_usdcx - input_usdcx
      if deposit <= 0 {
        False
      } else if !deposit_authorized(
        tranche,
        depositor,
        input_datum.curator,
        extra,
        inputs,
        input_datum.whitelist_policy,
      ) {
        False
      } else {
        when apply_deposit(input_datum, tranche, deposit) is {
          None -> False
          Some((expected, _minted)) ->
            output_datum == expected && input_datum.share_policy == output_datum.share_policy
        }
      }
    }
    Withdraw { tranche, shares } -> {
      let payout = input_usdcx - output_usdcx
      if payout <= 0 {
        False
      } else {
        when apply_withdraw(input_datum, tranche, shares) is {
          None -> False
          Some((expected, expected_payout)) ->
            expected_payout == payout && output_datum == expected
        }
      }
    }
    UpdateConfig { config } -> and {
        signed_by(extra, input_datum.curator),
        input_usdcx == output_usdcx,
        input_datum.senior_shares == output_datum.senior_shares,
        input_datum.junior_shares == output_datum.junior_shares,
        input_datum.senior_assets == output_datum.senior_assets,
        input_datum.junior_assets == output_datum.junior_assets,
        output_datum == apply_config_update(input_datum, config),
      }
    Disburse {
      principal,
      borrower,
      revenue_share_bps,
      repayment_cap,
      loan_asset_name,
    } -> {
      let payout = input_usdcx - output_usdcx
      let existing = exposure_from_reference_inputs(
        reference_inputs,
        input_datum.credit_script,
        borrower,
      )
      let tvl = vault_tvl(input_usdcx, input_datum.deployed_outstanding)
      let expected_loan = expected_open_loan(
        vault_script,
        input_datum.credit_script,
        borrower,
        principal,
        revenue_share_bps,
        repayment_cap,
      )
      if payout != principal {
        False
      } else if !signed_by(extra, input_datum.curator) {
        False
      } else if !within_concentration_limit(
        existing,
        principal,
        tvl,
        input_datum.config.max_single_borrower_bps,
      ) {
        False
      } else {
        when apply_disburse(input_datum, principal) is {
          None -> False
          Some(expected_datum) -> and {
              output_datum == expected_datum,
              input_datum.senior_shares == output_datum.senior_shares,
              input_datum.junior_shares == output_datum.junior_shares,
              input_datum.senior_assets == output_datum.senior_assets,
              input_datum.junior_assets == output_datum.junior_assets,
              validate_loan_output(
                outputs,
                input_datum.credit_script,
                expected_loan,
              ),
              usdcx_paid_to_borrower(
                outputs,
                input_datum.usdcx_policy,
                borrower,
                principal,
              ),
              loan_asset_name != #"",
            }
        }
      }
    }
    RecordRepayment { principal_paid, interest_paid } ->
      validate_vault_repay(
        input_datum,
        output_datum,
        principal_paid,
        interest_paid,
        input_usdcx,
        output_usdcx,
        outputs,
      )
  }
}

pub fn share_deltas_for_redeemer(
  input_datum: VaultDatum,
  _output_datum: VaultDatum,
  redeemer: VaultRedeemer,
  input_usdcx: Int,
  output_usdcx: Int,
) -> Option<(Int, Int)> {
  when redeemer is {
    Deposit { tranche, .. } -> {
      let deposit = output_usdcx - input_usdcx
      when apply_deposit(input_datum, tranche, deposit) is {
        None -> None
        Some((_, minted)) ->
          when tranche is {
            Senior -> Some((minted, 0))
            Junior -> Some((0, minted))
          }
      }
    }
    Withdraw { tranche, shares } ->
      when apply_withdraw(input_datum, tranche, shares) is {
        None -> None
        Some(_) ->
          when tranche is {
            Senior -> Some((-shares, 0))
            Junior -> Some((0, -shares))
          }
      }
    UpdateConfig { .. } -> Some((0, 0))
    Disburse { .. } -> Some((0, 0))
    RecordRepayment { .. } -> Some((0, 0))
  }
}

pub fn validate_share_mint(
  mint: Assets,
  share_policy: PolicyId,
  senior_delta: Int,
  junior_delta: Int,
) -> Bool {
  and {
    quantity_of(mint, share_policy, senior_share_asset_name()) == senior_delta,
    quantity_of(mint, share_policy, junior_share_asset_name()) == junior_delta,
  }
}

pub fn transaction_has_spend(self: Transaction) -> Bool {
  list.any(
    self.redeemers,
    fn(pair) {
      when pair.1st is {
        Spend(_) -> True
        _ -> False
      }
    },
  )
}

test deposit_authorized_senior_needs_whitelist() {
  let curator = #"aa"
  let depositor = #"bb"
  let policy = #"1111111111111111111111111111111111111111111111111111111111"
  let kyc_input = Input {
    output_reference: OutputReference {
      transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
      output_index: 0,
    },
    output: Output {
      address: from_verification_key(depositor),
      value: from_asset(policy, whitelist_asset_name(), 1),
      datum: NoDatum,
      reference_script: None,
    },
  }
  deposit_authorized(Senior, depositor, curator, [], [kyc_input], policy)
}

test deposit_authorized_junior_needs_curator() {
  let policy = #"1111111111111111111111111111111111111111111111111111111111"
  deposit_authorized(Junior, #"bb", #"aa", [#"aa"], [], policy)
}

test deposit_authorized_junior_fails_without_curator() {
  let policy = #"1111111111111111111111111111111111111111111111111111111111"
  !deposit_authorized(Junior, #"bb", #"aa", [], [], policy)
}

test validate_update_config_keeps_balances() {
  let config = VaultConfig {
    max_single_borrower_bps: 1_000,
    protocol_fee_bps: 200,
    curator_fee_bps: 100,
    senior_rate_bps: 8_000,
    attester: #"11",
    protocol_treasury: #"22",
  }
  let datum = VaultDatum {
    curator: #"aa",
    usdcx_policy: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    whitelist_policy: #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    share_policy: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    credit_script: #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    config,
    senior_shares: 100,
    junior_shares: 50,
    senior_assets: 1_000,
    junior_assets: 500,
    deployed_outstanding: 0,
  }
  let new_config = VaultConfig {
    max_single_borrower_bps: 800,
    protocol_fee_bps: 200,
    curator_fee_bps: 100,
    senior_rate_bps: 8_000,
    attester: #"11",
    protocol_treasury: #"22",
  }
  let vault_script = #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  validate_vault_spend(
    vault_script,
    datum,
    apply_config_update(datum, new_config),
    UpdateConfig { config: new_config },
    10_000,
    10_000,
    [#"aa"],
    [],
    [],
    [],
  )
}

test validate_deposit_senior_without_whitelist_fails() {
  let config = VaultConfig {
    max_single_borrower_bps: 1_000,
    protocol_fee_bps: 200,
    curator_fee_bps: 100,
    senior_rate_bps: 8_000,
    attester: #"11",
    protocol_treasury: #"22",
  }
  let datum = VaultDatum {
    curator: #"aa",
    usdcx_policy: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    whitelist_policy: #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    share_policy: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    credit_script: #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    config,
    senior_shares: 0,
    junior_shares: 0,
    senior_assets: 0,
    junior_assets: 0,
    deployed_outstanding: 0,
  }
  when apply_deposit(datum, Senior, 1_000) is {
    None -> False
    Some((expected, _)) ->
      !validate_vault_spend(
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        datum,
        expected,
        Deposit { tranche: Senior, depositor: #"bb" },
        0,
        1_000,
        [],
        [],
        [],
        [],
      )
  }
}

test validate_disburse_rejects_over_concentration() {
  let config = VaultConfig {
    max_single_borrower_bps: 1_000,
    protocol_fee_bps: 200,
    curator_fee_bps: 100,
    senior_rate_bps: 8_000,
    attester: #"11",
    protocol_treasury: #"22",
  }
  let datum = VaultDatum {
    curator: #"aa",
    usdcx_policy: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    whitelist_policy: #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    share_policy: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    credit_script: #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    config,
    senior_shares: 100,
    junior_shares: 0,
    senior_assets: 10_000,
    junior_assets: 0,
    deployed_outstanding: 0,
  }
  when apply_disburse(datum, 2_000) is {
    None -> False
    Some(next) ->
      !validate_vault_spend(
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        datum,
        next,
        Disburse {
          principal: 2_000,
          borrower: #"bb",
          revenue_share_bps: 500,
          repayment_cap: 3_000,
          loan_asset_name: #"6c6f616e31",
        },
        10_000,
        8_000,
        [#"aa"],
        [],
        [],
        [],
      )
  }
}

test validate_share_mint_rejects_wrong_delta() {
  let policy = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  !validate_share_mint(zero, policy, 100, 0)
}

test validate_withdraw_over_shares_fails() {
  let config = VaultConfig {
    max_single_borrower_bps: 1_000,
    protocol_fee_bps: 200,
    curator_fee_bps: 100,
    senior_rate_bps: 8_000,
    attester: #"11",
    protocol_treasury: #"22",
  }
  let datum = VaultDatum {
    curator: #"aa",
    usdcx_policy: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    whitelist_policy: #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    share_policy: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    credit_script: #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    config,
    senior_shares: 100,
    junior_shares: 0,
    senior_assets: 1_000,
    junior_assets: 0,
    deployed_outstanding: 0,
  }
  !validate_vault_spend(
    #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    datum,
    datum,
    Withdraw { tranche: Senior, shares: 101 },
    1_000,
    900,
    [],
    [],
    [],
    [],
  )
}
