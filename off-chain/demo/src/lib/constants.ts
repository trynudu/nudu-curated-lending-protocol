/** Match lib/constants.ak (hex asset names). */
export const SENIOR_SHARE_NAME = "73656e696f72";
export const JUNIOR_SHARE_NAME = "6a756e696f72";
export const WHITELIST_ASSET_NAME = "6b7963";
/** Pilot “USDCx” uses empty asset name like on-chain constants. */
export const USDCX_ASSET_NAME = "";

export const DEFAULT_VAULT_CONFIG = {
  max_single_borrower_bps: 1_000n,
  protocol_fee_bps: 200n,
  curator_fee_bps: 1_000n,
  senior_rate_bps: 8_000n,
} as const;
