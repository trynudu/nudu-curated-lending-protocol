use aiken/crypto.{ScriptHash}
use aiken/interval
use cardano/address.{from_script, from_verification_key}
use cardano/assets.{PolicyId, from_asset, zero}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Redeemer, Spend,
  Transaction, placeholder,
}
use constants.{usdcx_asset_name}
use credit_logic.{expected_open_loan, validate_credit_repay}
use repay_logic.{apply_repay}
use test_vectors.{
  test_attester_signature, test_attester_vkey, test_attester_vkey_hash,
  test_revenue_attestation,
}
use types.{
  Active, LoanDatum, RecordRepayment, Repay, RevenueAttestation, VaultConfig,
  VaultDatum,
}

const vault_script: ScriptHash =
  #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

const credit_script: ScriptHash =
  #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const usdcx_policy: PolicyId =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const loan_ref: OutputReference =
  OutputReference {
    transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
    output_index: 1,
  }

const vault_ref: OutputReference =
  OutputReference {
    transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
    output_index: 0,
  }

fn sample_vault_config() -> VaultConfig {
  VaultConfig {
    max_single_borrower_bps: 1_000,
    protocol_fee_bps: 200,
    curator_fee_bps: 1_000,
    senior_rate_bps: 8_000,
    attester: test_attester_vkey_hash(),
    protocol_treasury: #"22",
  }
}

fn sample_vault_in() -> VaultDatum {
  VaultDatum {
    curator: #"aa",
    usdcx_policy,
    whitelist_policy: #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    share_policy: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    credit_script,
    config: sample_vault_config(),
    senior_shares: 100,
    junior_shares: 50,
    senior_assets: 1_000,
    junior_assets: 500,
    deployed_outstanding: 5_000,
  }
}

fn sample_loan() -> LoanDatum {
  LoanDatum {
    ..expected_open_loan(vault_script, credit_script, #"bb", 5_000, 500, 20_000),
    outstanding_principal: 4_000,
    total_repaid: 1_000,
    status: Active,
  }
}

pub fn sample_repay_transaction() -> Transaction {
  let principal_paid = 500
  let interest_paid = 10_000
  let vault_in = sample_vault_in()
  expect Some((vault_out, alloc)) = apply_repay(
    vault_in,
    principal_paid,
    interest_paid,
  )
  let vault_in_usdcx = 50_000
  let vault_out_usdcx = vault_in_usdcx + principal_paid + interest_paid - alloc.protocol_fee - alloc.curator_fee
  let loan_in = sample_loan()
  let expected_loan = LoanDatum {
    ..loan_in,
    outstanding_principal: loan_in.outstanding_principal - principal_paid,
    total_repaid: loan_in.total_repaid + principal_paid + interest_paid,
    status: Active,
  }
  let attestation = test_revenue_attestation()
  let vault_spend: Redeemer = RecordRepayment { principal_paid, interest_paid }
  let credit_spend: Redeemer = Repay {
    principal_paid,
    interest_paid,
    attestation,
    attester_vkey: test_attester_vkey(),
    attester_signature: test_attester_signature(),
  }
  Transaction {
    ..placeholder,
    validity_range: interval.before(attestation.valid_until),
    extra_signatories: [loan_in.borrower],
    inputs: [
      Input {
        output_reference: vault_ref,
        output: Output {
          address: from_script(vault_script),
          value: from_asset(usdcx_policy, usdcx_asset_name(), vault_in_usdcx),
          datum: InlineDatum(vault_in),
          reference_script: None,
        },
      },
      Input {
        output_reference: loan_ref,
        output: Output {
          address: from_script(credit_script),
          value: zero,
          datum: InlineDatum(loan_in),
          reference_script: None,
        },
      },
      Input {
        output_reference: OutputReference {
          transaction_id: #"2222222222222222222222222222222222222222222222222222222222222222",
          output_index: 0,
        },
        output: Output {
          address: from_verification_key(loan_in.borrower),
          value: from_asset(
            usdcx_policy,
            usdcx_asset_name(),
            principal_paid + interest_paid,
          ),
          datum: NoDatum,
          reference_script: None,
        },
      },
    ],
    outputs: [
      Output {
        address: from_script(vault_script),
        value: from_asset(usdcx_policy, usdcx_asset_name(), vault_out_usdcx),
        datum: InlineDatum(vault_out),
        reference_script: None,
      },
      Output {
        address: from_script(credit_script),
        value: zero,
        datum: InlineDatum(expected_loan),
        reference_script: None,
      },
      Output {
        address: from_verification_key(vault_in.curator),
        value: from_asset(usdcx_policy, usdcx_asset_name(), alloc.curator_fee),
        datum: NoDatum,
        reference_script: None,
      },
      Output {
        address: from_verification_key(vault_in.config.protocol_treasury),
        value: from_asset(usdcx_policy, usdcx_asset_name(), alloc.protocol_fee),
        datum: NoDatum,
        reference_script: None,
      },
    ],
    redeemers: [
      Pair(Spend(vault_ref), vault_spend),
      Pair(Spend(loan_ref), credit_spend),
    ],
  }
}

test repay_end_to_end_passes_with_valid_attestation() {
  validate_credit_repay(
    sample_repay_transaction(),
    credit_script,
    sample_loan(),
    loan_ref,
    Repay {
      principal_paid: 500,
      interest_paid: 10_000,
      attestation: test_revenue_attestation(),
      attester_vkey: test_attester_vkey(),
      attester_signature: test_attester_signature(),
    },
  )
}

test repay_end_to_end_fails_with_tampered_attestation() {
  let bad_attestation = RevenueAttestation {
    ..test_revenue_attestation(),
    attested_revenue: 1,
  }
  !validate_credit_repay(
    sample_repay_transaction(),
    credit_script,
    sample_loan(),
    loan_ref,
    Repay {
      principal_paid: 500,
      interest_paid: 10_000,
      attestation: bad_attestation,
      attester_vkey: test_attester_vkey(),
      attester_signature: test_attester_signature(),
    },
  )
}
