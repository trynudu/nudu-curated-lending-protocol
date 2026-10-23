use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}

/// KYC whitelist token — curator-gated mint/burn (phase 1, unimplemented).
validator whitelist_policy {
  mint(_redeemer: Data, _policy_id: PolicyId, _self: Transaction) {
    False
  }

  else(_) {
    fail
  }
}
