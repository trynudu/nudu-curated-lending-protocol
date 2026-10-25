use aiken/crypto.{ScriptHash, VerificationKeyHash}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use credit_logic.{validate_credit_open, validate_credit_repay}
use types.{CreditSpendRedeemer, LoanDatum, OpenLoanRedeemer}

/// One UTxO per loan — mint opens; spend repays with vault `RecordRepayment`.
///
/// **Repay tx (expected):**
/// - Inputs: vault UTxO, loan UTxO, borrower USDCx.
/// - Outputs: continuing vault + loan, protocol/curator fee USDCx.
/// - Redeemers: vault `RecordRepayment`, credit `Repay` (includes attestation + Ed25519 sig).
/// - Signers: borrower; attestation binds attester via signature (vkey in redeemer).
validator credit(curator: VerificationKeyHash, credit_script: ScriptHash) {
  mint(redeemer: OpenLoanRedeemer, policy_id: PolicyId, self: Transaction) {
    validate_credit_open(self, policy_id, credit_script, curator, redeemer)
  }

  spend(
    datum: Option<LoanDatum>,
    redeemer: CreditSpendRedeemer,
    utxo: OutputReference,
    self: Transaction,
  ) {
    expect Some(loan) = datum
    validate_credit_repay(self, credit_script, loan, utxo, redeemer)
  }

  else(_) {
    fail
  }
}
