use aiken/crypto.{
  Signature, VerificationKey, VerificationKeyHash, blake2b_224, blake2b_256,
  verify_ed25519_signature,
}
use aiken/interval
use aiken/primitive/bytearray
use cardano/transaction.{OutputReference, ValidityRange}
use constants.{bps_denominator}
use types.{Active, LoanDatum, RevenueAttestation}

/// Domain separator for attestation signatures (ASCII `NUDU1`).
const attestation_domain: ByteArray = #"4e55445531"

/// Deterministic, documented payload for the attester's Ed25519 signature.
///
/// Layout (big-endian integers, fixed width):
/// `NUDU1 ‖ loan_tx_id(32) ‖ loan_index(u32) ‖ period_id(i64) ‖ attested_revenue(i64) ‖
///  principal_paid(i64) ‖ interest_paid(i64) ‖ valid_until(i64) ‖ nonce(i64)`
///
/// The attester signs `attestation_digest(attestation)` where the digest is Blake2b-256
/// over these bytes. Off-chain tooling must use the same layout (see `scripts/gen_attestation_test_vector.py`).
pub fn attestation_signing_bytes(att: RevenueAttestation) -> ByteArray {
  let ref_part = bytearray.concat(
    att.loan_ref.transaction_id,
    bytearray.from_int_big_endian(att.loan_ref.output_index, 4),
  )
  let ints = bytearray.concat(
    bytearray.from_int_big_endian(att.period_id, 8),
    bytearray.from_int_big_endian(att.attested_revenue, 8),
  )
  let ints2 = bytearray.concat(
    bytearray.from_int_big_endian(att.principal_paid, 8),
    bytearray.from_int_big_endian(att.interest_paid, 8),
  )
  let ints3 = bytearray.concat(
    bytearray.from_int_big_endian(att.valid_until, 8),
    bytearray.from_int_big_endian(att.nonce, 8),
  )
  bytearray.concat(
    attestation_domain,
    bytearray.concat(
      ref_part,
      bytearray.concat(ints, bytearray.concat(ints2, ints3)),
    ),
  )
}

pub fn attestation_digest(att: RevenueAttestation) -> ByteArray {
  blake2b_256(attestation_signing_bytes(att))
}

pub fn verification_key_hash(key: VerificationKey) -> VerificationKeyHash {
  blake2b_224(key)
}

pub fn attestation_not_expired(
  validity: ValidityRange,
  valid_until: Int,
) -> Bool {
  validity |> interval.is_entirely_before(valid_until)
}

pub fn max_repayment_for_revenue(
  attested_revenue: Int,
  revenue_share_bps: Int,
) -> Int {
  attested_revenue * revenue_share_bps / bps_denominator
}

pub fn attestation_matches_repay_amounts(
  att: RevenueAttestation,
  principal_paid: Int,
  interest_paid: Int,
) -> Bool {
  and {
    att.principal_paid == principal_paid,
    att.interest_paid == interest_paid,
  }
}

pub fn attestation_binds_loan(
  att: RevenueAttestation,
  loan_ref: OutputReference,
) -> Bool {
  att.loan_ref == loan_ref
}

pub fn validate_revenue_attestation(
  att: RevenueAttestation,
  loan_ref: OutputReference,
  loan: LoanDatum,
  attester_vkh: VerificationKeyHash,
  attester_vkey: VerificationKey,
  attester_signature: Signature,
  validity: ValidityRange,
  principal_paid: Int,
  interest_paid: Int,
) -> Bool {
  let payment_total = principal_paid + interest_paid
  let max_payment = max_repayment_for_revenue(
    att.attested_revenue,
    loan.revenue_share_bps,
  )
  and {
    attestation_binds_loan(att, loan_ref),
    attestation_matches_repay_amounts(att, principal_paid, interest_paid),
    verification_key_hash(attester_vkey) == attester_vkh,
    verify_ed25519_signature(
      attester_vkey,
      attestation_digest(att),
      attester_signature,
    ),
    attestation_not_expired(validity, att.valid_until),
    payment_total <= max_payment,
    loan.total_repaid + payment_total <= loan.repayment_cap,
  }
}

test validate_revenue_attestation_rejects_wrong_loan_ref() {
  let att = RevenueAttestation {
    loan_ref: OutputReference {
      transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
      output_index: 0,
    },
    period_id: 202_601,
    attested_revenue: 100_000,
    principal_paid: 500,
    interest_paid: 50,
    valid_until: 1_000_000_000_000,
    nonce: 1,
  }
  let loan = LoanDatum {
    vault_script: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    credit_script: #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    borrower: #"bb",
    principal: 10_000,
    outstanding_principal: 10_000,
    revenue_share_bps: 500,
    repayment_cap: 20_000,
    total_repaid: 0,
    status: Active,
  }
  !validate_revenue_attestation(
    att,
    OutputReference {
      transaction_id: #"2222222222222222222222222222222222222222222222222222222222222222",
      output_index: 0,
    },
    loan,
    #"11",
    #"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
    #"00",
    interval.everything,
    500,
    50,
  )
}

test validate_revenue_attestation_rejects_over_revenue_share() {
  let loan_ref = OutputReference {
    transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
    output_index: 0,
  }
  let att = RevenueAttestation {
    loan_ref,
    period_id: 202_601,
    attested_revenue: 1_000,
    principal_paid: 500,
    interest_paid: 50,
    valid_until: 1_000_000_000_000,
    nonce: 1,
  }
  let loan = LoanDatum {
    vault_script: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    credit_script: #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    borrower: #"bb",
    principal: 10_000,
    outstanding_principal: 10_000,
    revenue_share_bps: 500,
    repayment_cap: 20_000,
    total_repaid: 0,
    status: Active,
  }
  !validate_revenue_attestation(
    att,
    loan_ref,
    loan,
    #"11",
    #"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
    #"00",
    interval.everything,
    500,
    50,
  )
}
