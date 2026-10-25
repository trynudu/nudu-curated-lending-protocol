use aiken/crypto.{Signature, VerificationKey, VerificationKeyHash}
use aiken/interval
use attestation.{validate_revenue_attestation}
use cardano/transaction.{OutputReference}
use types.{Active, LoanDatum, RevenueAttestation}

/// Test attester key (seed 0x01×32). Used only in unit tests — never use on mainnet.
pub fn test_attester_vkey() -> VerificationKey {
  #"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c"
}

pub fn test_attester_vkey_hash() -> VerificationKeyHash {
  #"0d6a577e9441ad8ed9663931906e4d43ece8f82c712b1d0235affb06"
}

pub fn test_revenue_attestation() -> RevenueAttestation {
  RevenueAttestation {
    loan_ref: OutputReference {
      transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
      output_index: 1,
    },
    period_id: 202_601,
    attested_revenue: 500_000,
    principal_paid: 500,
    interest_paid: 10_000,
    valid_until: 1_000_000_000_000,
    nonce: 42,
  }
}

/// Ed25519 signature over `attestation_digest(test_revenue_attestation())`.
/// Regenerate with: `python3 scripts/gen_attestation_test_vector.py`
pub fn test_attester_signature() -> Signature {
  #"08b1696b34670ea7592f1794485fd13be1e597cd1434aecbb53894c7619a23319a664e3dfb1997215df0ed8a528d7aaed367773f27641ac05bfeba1331a43d0a"
}

test validate_revenue_attestation_accepts_test_vector() {
  let att = test_revenue_attestation()
  let loan = LoanDatum {
    vault_script: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    credit_script: #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    borrower: #"bb",
    principal: 5_000,
    outstanding_principal: 4_000,
    revenue_share_bps: 500,
    repayment_cap: 20_000,
    total_repaid: 1_000,
    status: Active,
  }
  validate_revenue_attestation(
    att,
    att.loan_ref,
    loan,
    test_attester_vkey_hash(),
    test_attester_vkey(),
    test_attester_signature(),
    interval.before(att.valid_until),
    att.principal_paid,
    att.interest_paid,
  )
}
