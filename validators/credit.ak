use cardano/transaction.{OutputReference, Transaction}
use types.{LoanDatum}

/// One UTxO per loan — disburse and repay (phase 1, unimplemented).
validator credit {
  spend(
    _datum: Option<LoanDatum>,
    _redeemer: Data,
    _utxo: OutputReference,
    _self: Transaction,
  ) {
    False
  }

  else(_) {
    fail
  }
}
