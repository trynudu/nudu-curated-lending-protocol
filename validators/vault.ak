use cardano/transaction.{OutputReference, Transaction}
use types.{VaultDatum}

/// Tranched vault — deposit, withdraw, and disburse (phase 1, unimplemented).
validator vault {
  spend(
    _datum: Option<VaultDatum>,
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
