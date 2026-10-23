use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}

/// Mints/burns senior and junior share tokens (phase 1, unimplemented).
validator share_policy {
  mint(_redeemer: Data, _policy_id: PolicyId, _self: Transaction) {
    False
  }

  else(_) {
    fail
  }
}
