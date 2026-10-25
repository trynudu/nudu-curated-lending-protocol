use aiken/crypto.{ScriptHash, VerificationKeyHash}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use credit_logic.{validate_credit_open, validate_credit_repay}
use types.{CreditSpendRedeemer, LoanDatum, OpenLoanRedeemer}

/// One UTxO per loan — mint opens; spend repays with vault `RecordRepayment`.
validator credit(curator: VerificationKeyHash, credit_script: ScriptHash) {
  mint(redeemer: OpenLoanRedeemer, policy_id: PolicyId, self: Transaction) {
    validate_credit_open(self, policy_id, credit_script, curator, redeemer)
  }

  spend(
    datum: Option<LoanDatum>,
    redeemer: CreditSpendRedeemer,
    _utxo: OutputReference,
    self: Transaction,
  ) {
    expect Some(loan) = datum
    validate_credit_repay(self, credit_script, loan, redeemer)
  }

  else(_) {
    fail
  }
}
