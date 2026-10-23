use cardano/assets.{AssetName}
use constants.{junior_share_asset_name, senior_share_asset_name}

pub type Tranche {
  Senior
  Junior
}

pub type VaultDatum {
  /// Curator public key hash (Ed25519)
  curator: ByteArray,
  /// USDCx policy id (placeholder until preprod params are wired)
  usdcx_policy: ByteArray,
  max_single_borrower_bps: Int,
  protocol_fee_bps: Int,
  curator_fee_bps: Int,
  senior_rate_bps: Int,
}

pub type LoanStatus {
  PendingDisburse
  Active
  Repaid
  Defaulted
}

pub type LoanDatum {
  vault_policy: ByteArray,
  borrower: ByteArray,
  principal: Int,
  outstanding_principal: Int,
  revenue_share_bps: Int,
  repayment_cap: Int,
  status: LoanStatus,
}

/// Result of applying the interest waterfall (principal is handled separately).
pub type WaterfallAllocation {
  protocol_fee: Int,
  curator_fee: Int,
  senior_interest: Int,
  junior_interest: Int,
}

pub fn tranche_share_name(tranche: Tranche) -> AssetName {
  when tranche is {
    Senior -> senior_share_asset_name()
    Junior -> junior_share_asset_name()
  }
}
