use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
use types.{ShareMintRedeemer}
use vault_logic.{transaction_has_spend, validate_share_mint}

/// Mints/burns senior and junior share tokens only alongside a vault spend.
validator share_policy {
  mint(redeemer: ShareMintRedeemer, policy_id: PolicyId, self: Transaction) {
    and {
      transaction_has_spend(self),
      validate_share_mint(
        self.mint,
        policy_id,
        redeemer.senior_delta,
        redeemer.junior_delta,
      ),
    }
  }

  else(_) {
    fail
  }
}
