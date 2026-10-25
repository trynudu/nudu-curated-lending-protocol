use aiken/collection/list
use aiken/crypto.{ScriptHash, VerificationKeyHash}
use auth.{signed_by}
use cardano/address.{Script, VerificationKey}
use cardano/assets.{AssetName, Assets, PolicyId, quantity_of}
use cardano/transaction.{InlineDatum, Input, Output, Transaction, placeholder}
use constants.{bps_denominator, usdcx_asset_name}
use types.{
  Active, CreditMintRedeemer, LoanDatum, LoanStatus, Open, PendingDisburse,
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
  credit_script: ScriptHash,
  borrower: VerificationKeyHash,
  principal: Int,
  revenue_share_bps: Int,
  repayment_cap: Int,
) -> LoanDatum {
  LoanDatum {
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
  redeemer: CreditMintRedeemer,
) -> Bool {
  expect  
      Open {
        borrower,
        principal,
        revenue_share_bps,
        repayment_cap,
        loan_asset_name,
      }
    = redeemer
  let expected = expected_open_loan(
    credit_script,
    borrower,
    principal,
    revenue_share_bps,
    repayment_cap,
  )
  and {
    signed_by(self.extra_signatories, curator),
    validate_open_mint(self.mint, policy_id, loan_asset_name),
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
    Open {
      borrower: #"bb",
      principal: 1_000,
      revenue_share_bps: 500,
      repayment_cap: 2_000,
      loan_asset_name: #"6c6f616e31",
    },
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
