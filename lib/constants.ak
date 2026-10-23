/// Shared on-chain constants (single source — do not duplicate literals in validators).
pub const bps_denominator: Int = 10_000

/// Default max exposure to one borrower as a fraction of vault TVL (10%).
pub const default_max_single_borrower_bps: Int = 1_000

pub fn senior_share_asset_name() -> ByteArray {
  @"senior"
}

pub fn junior_share_asset_name() -> ByteArray {
  @"junior"
}

pub fn whitelist_asset_name() -> ByteArray {
  @"kyc"
}
