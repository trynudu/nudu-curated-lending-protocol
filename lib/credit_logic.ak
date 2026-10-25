use aiken/collection/list
use aiken/crypto.{ScriptHash, VerificationKeyHash}
use auth.{signed_by}
use cardano/address.{Script, VerificationKey}
use cardano/assets.{AssetName, Assets, PolicyId, quantity_of}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Redeemer, ScriptPurpose, Spend,
  Transaction, placeholder,
}
use constants.{bps_denominator, usdcx_asset_name}
use repay_logic.{validate_vault_repay}
use types.{
  Active, CreditSpendRedeemer, LoanDatum, LoanStatus, OpenLoanRedeemer,
  PendingDisburse, RecordRepayment, Repaid, Repay, VaultDatum, VaultRedeemer,
}

pub fn vault_tvl(liquid_usdcx: Int, deployed_outstanding: Int) -> Int {
  liquid_usdcx + deployed_outstanding
}

pub fn within_concentration_limit(
  existing_exposure: Int,
  new_principal: Int,
  vault_tvl: Int,
  max_single_borrower_bps: Int,
) -> Bool {
  if vault_tvl <= 0 || new_principal <= 0 {
    False
  } else {
    ( existing_exposure + new_principal ) * bps_denominator <= vault_tvl * max_single_borrower_bps
  }
}

pub fn loan_is_active_or_pending(status: LoanStatus) -> Bool {
  when status is {
    Active -> True
    PendingDisburse -> True
    _ -> False
  }
}

pub fn exposure_from_reference_inputs(
  reference_inputs: List<Input>,
  credit_script: ScriptHash,
  borrower: VerificationKeyHash,
) -> Int {
  list.foldl(
    reference_inputs,
    0,
    fn(input, acc) {
      when input.output.address.payment_credential is {
        Script(hash) ->
          if hash == credit_script {
            acc + loan_outstanding_from_output(input.output, borrower)
          } else {
            acc
          }
        _ -> acc
      }
    },
  )
}

fn loan_outstanding_from_output(
  output: Output,
  borrower: VerificationKeyHash,
) -> Int {
  when output.datum is {
    InlineDatum(raw) -> {
      expect loan: LoanDatum = raw
      if loan.borrower == borrower && loan_is_active_or_pending(loan.status) {
        loan.outstanding_principal
      } else {
        0
      }
    }
    _ -> 0
  }
}

pub fn expected_open_loan(
  vault_script: ScriptHash,
  credit_script: ScriptHash,
  borrower: VerificationKeyHash,
  principal: Int,
  revenue_share_bps: Int,
  repayment_cap: Int,
) -> LoanDatum {
  LoanDatum {
    vault_script,
    credit_script,
    borrower,
    principal,
    outstanding_principal: principal,
    revenue_share_bps,
    repayment_cap,
    status: Active,
  }
}

pub fn validate_loan_output(
  outputs: List<Output>,
  credit_script: ScriptHash,
  expected: LoanDatum,
) -> Bool {
  list.any(
    outputs,
    fn(out) {
      when out.address.payment_credential is {
        Script(hash) ->
          if hash == credit_script {
            when out.datum is {
              InlineDatum(raw) -> {
                expect loan: LoanDatum = raw
                loan == expected
              }
              _ -> False
            }
          } else {
            False
          }
        _ -> False
      }
    },
  )
}

pub fn usdcx_paid_to_borrower(
  outputs: List<Output>,
  usdcx_policy: PolicyId,
  borrower: VerificationKeyHash,
  min_amount: Int,
) -> Bool {
  list.any(
    outputs,
    fn(out) {
      when out.address.payment_credential is {
        VerificationKey(vkh) ->
          if vkh == borrower {
            quantity_of(out.value, usdcx_policy, usdcx_asset_name()) >= min_amount
          } else {
            False
          }
        _ -> False
      }
    },
  )
}

pub fn validate_open_mint(
  mint: Assets,
  policy_id: PolicyId,
  loan_asset_name: AssetName,
) -> Bool {
  quantity_of(mint, policy_id, loan_asset_name) == 1
}

test within_concentration_limit_allows_ten_percent() {
  within_concentration_limit(
    existing_exposure: 0,
    new_principal: 1_000,
    vault_tvl: 10_000,
    max_single_borrower_bps: 1_000,
  )
}

pub fn validate_credit_open(
  self: Transaction,
  policy_id: PolicyId,
  credit_script: ScriptHash,
  curator: VerificationKeyHash,
  redeemer: OpenLoanRedeemer,
) -> Bool {
  let expected = expected_open_loan(
    redeemer.vault_script,
    credit_script,
    redeemer.borrower,
    redeemer.principal,
    redeemer.revenue_share_bps,
    redeemer.repayment_cap,
  )
  and {
    signed_by(self.extra_signatories, curator),
    validate_open_mint(self.mint, policy_id, redeemer.loan_asset_name),
    validate_loan_output(self.outputs, credit_script, expected),
  }
}

test validate_credit_open_fails_without_curator() {
  let credit_script = #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  let policy = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  !validate_credit_open(
    placeholder,
    policy,
    credit_script,
    #"aa",
    OpenLoanRedeemer {
      vault_script: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      borrower: #"bb",
      principal: 1_000,
      revenue_share_bps: 500,
      repayment_cap: 2_000,
      loan_asset_name: #"6c6f616e31",
    },
  )
}

pub fn apply_loan_repay(
  loan: LoanDatum,
  principal_paid: Int,
) -> Option<LoanDatum> {
  if principal_paid <= 0 || principal_paid > loan.outstanding_principal {
    None
  } else {
    let remaining = loan.outstanding_principal - principal_paid
    Some(
      LoanDatum {
        ..loan,
        outstanding_principal: remaining,
        status: if remaining == 0 {
          Repaid
        } else {
          Active
        },
      },
    )
  }
}

pub fn usdcx_from_borrower_inputs(
  inputs: List<Input>,
  usdcx_policy: PolicyId,
  borrower: VerificationKeyHash,
) -> Int {
  list.foldl(
    inputs,
    0,
    fn(input, acc) {
      when input.output.address.payment_credential is {
        VerificationKey(vkh) ->
          if vkh == borrower {
            acc + quantity_of(
              input.output.value,
              usdcx_policy,
              usdcx_asset_name(),
            )
          } else {
            acc
          }
        _ -> acc
      }
    },
  )
}

fn vault_repay_redeemer(
  redeemers: Pairs<ScriptPurpose, Redeemer>,
  vault_input_ref: OutputReference,
) -> Option<VaultRedeemer> {
  list.foldl(
    redeemers,
    None,
    fn(pair, acc) {
      when acc is {
        Some(_) -> acc
        None ->
          when pair.1st is {
            Spend(ref) ->
              if ref == vault_input_ref {
                expect redeemer: VaultRedeemer = pair.2nd
                Some(redeemer)
              } else {
                None
              }
            _ -> None
          }
      }
    },
  )
}

fn continuing_vault_output(
  outputs: List<Output>,
  vault_script: ScriptHash,
  usdcx_policy: PolicyId,
) -> Option<(Output, VaultDatum, Int)> {
  list.foldl(
    outputs,
    None,
    fn(out, acc) {
      when acc is {
        Some(_) -> acc
        None ->
          when out.address.payment_credential is {
            Script(hash) ->
              if hash == vault_script {
                when out.datum is {
                  InlineDatum(raw) -> {
                    expect datum: VaultDatum = raw
                    let usdcx = quantity_of(
                      out.value,
                      usdcx_policy,
                      usdcx_asset_name(),
                    )
                    Some((out, datum, usdcx))
                  }
                  _ -> None
                }
              } else {
                None
              }
            _ -> None
          }
      }
    },
  )
}

fn spent_vault_io(
  inputs: List<Input>,
  outputs: List<Output>,
  vault_script: ScriptHash,
) -> Option<(OutputReference, VaultDatum, VaultDatum, Int, Int)> {
  list.foldl(
    inputs,
    None,
    fn(input, acc) {
      when acc is {
        Some(_) -> acc
        None ->
          when input.output.address.payment_credential is {
            Script(hash) ->
              if hash == vault_script {
                when input.output.datum is {
                  InlineDatum(raw_in) -> {
                    expect in_datum: VaultDatum = raw_in
                    when
                      continuing_vault_output(
                        outputs,
                        vault_script,
                        in_datum.usdcx_policy,
                      )
                    is {
                      None -> None
                      Some((out, out_datum, out_usdcx)) -> {
                        let in_usdcx = quantity_of(
                          input.output.value,
                          in_datum.usdcx_policy,
                          usdcx_asset_name(),
                        )
                        Some(
                          (
                            input.output_reference,
                            in_datum,
                            out_datum,
                            in_usdcx,
                            out_usdcx,
                          ),
                        )
                      }
                    }
                  }
                  _ -> None
                }
              } else {
                None
              }
            _ -> None
          }
      }
    },
  )
}

pub fn validate_loan_repay_output(
  outputs: List<Output>,
  credit_script: ScriptHash,
  expected: LoanDatum,
) -> Bool {
  validate_loan_output(outputs, credit_script, expected)
}

pub fn validate_credit_repay(
  self: Transaction,
  credit_script: ScriptHash,
  loan: LoanDatum,
  redeemer: CreditSpendRedeemer,
) -> Bool {
  when redeemer is {
    Repay { principal_paid, interest_paid } -> {
      let payment_total = principal_paid + interest_paid
      if loan.status != Active || payment_total <= 0 {
        False
      } else if !signed_by(self.extra_signatories, loan.borrower) {
        False
      } else if interest_paid < 0 {
        False
      } else {
        when spent_vault_io(self.inputs, self.outputs, loan.vault_script) is {
          None -> False
          Some((vault_ref, vault_in, vault_out, vault_in_usdcx, vault_out_usdcx)) ->
            when vault_repay_redeemer(self.redeemers, vault_ref) is {
              None -> False
              Some(RecordRepayment { principal_paid: vp, interest_paid: vi }) ->
                if vp != principal_paid || vi != interest_paid {
                  False
                } else if !signed_by(
                  self.extra_signatories,
                  vault_in.config.attester,
                ) {
                  False
                } else if !validate_vault_repay(
                  vault_in,
                  vault_out,
                  principal_paid,
                  interest_paid,
                  vault_in_usdcx,
                  vault_out_usdcx,
                  self.outputs,
                ) {
                  False
                } else {
                  when apply_loan_repay(loan, principal_paid) is {
                    None -> False
                    Some(expected_loan) -> {
                      let borrower_paid = usdcx_from_borrower_inputs(
                        self.inputs,
                        vault_in.usdcx_policy,
                        loan.borrower,
                      )
                      and {
                        borrower_paid >= payment_total,
                        validate_loan_repay_output(
                          self.outputs,
                          credit_script,
                          expected_loan,
                        ),
                      }
                    }
                  }
                }
              _ -> False
            }
        }
      }
    }
  }
}

test validate_credit_repay_fails_without_attester() {
  let vault_script = #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  let credit_script = #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  let loan = expected_open_loan(
    vault_script,
    credit_script,
    #"bb",
    1_000,
    500,
    2_000,
  )
  !validate_credit_repay(
    placeholder,
    credit_script,
    loan,
    Repay { principal_paid: 100, interest_paid: 10 },
  )
}

test within_concentration_limit_rejects_over_cap() {
  !within_concentration_limit(
    existing_exposure: 500,
    new_principal: 600,
    vault_tvl: 10_000,
    max_single_borrower_bps: 1_000,
  )
}
