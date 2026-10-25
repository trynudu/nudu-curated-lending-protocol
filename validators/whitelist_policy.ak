use aiken/crypto.{VerificationKeyHash}
use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
use types.{BurnKyc, MintKyc, WhitelistRedeemer}
use whitelist_logic.{validate_burn_kyc, validate_mint_kyc}

/// KYC whitelist token — curator-gated mint/burn (one `kyc` asset per holder).
validator whitelist_policy(curator: VerificationKeyHash) {
  mint(redeemer: WhitelistRedeemer, policy_id: PolicyId, self: Transaction) {
    when redeemer is {
      MintKyc { holder } -> validate_mint_kyc(self, policy_id, curator, holder)
      BurnKyc { holder } -> validate_burn_kyc(self, policy_id, curator, holder)
    }
  }

  else(_) {
    fail
  }
}
