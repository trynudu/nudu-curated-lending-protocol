use aiken/crypto.{ScriptHash, VerificationKeyHash}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use credit_logic.{validate_credit_open}
use types.{CreditSpendRedeemer, LoanDatum, OpenLoanRedeemer}

/// One UTxO per loan — mint opens; spend repays (repay not yet implemented).
validator credit(curator: VerificationKeyHash, credit_script: ScriptHash) {
  mint(redeemer: OpenLoanRedeemer, policy_id: PolicyId, self: Transaction) {
    validate_credit_open(self, policy_id, credit_script, curator, redeemer)
  }

  spend(
    _datum: Option<LoanDatum>,
    _redeemer: CreditSpendRedeemer,
    _utxo: OutputReference,
    _self: Transaction,
  ) {
    False
  }

  else(_) {
    fail
  }
}
