use aiken/crypto.{ScriptHash, VerificationKeyHash}
use cardano/assets.{AssetName, PolicyId}
use constants.{junior_share_asset_name, senior_share_asset_name}

pub type Tranche {
  Senior
  Junior
}

/// Fee and risk parameters updatable by the curator without moving vault funds.
pub type VaultConfig {
  max_single_borrower_bps: Int,
  protocol_fee_bps: Int,
  curator_fee_bps: Int,
  senior_rate_bps: Int,
}

pub type VaultDatum {
  curator: VerificationKeyHash,
  usdcx_policy: PolicyId,
  whitelist_policy: PolicyId,
  share_policy: PolicyId,
  credit_script: ScriptHash,
  config: VaultConfig,
  senior_shares: Int,
  junior_shares: Int,
  senior_assets: Int,
  junior_assets: Int,
  /// USDCx currently deployed in active loans (NAV still counts this).
  deployed_outstanding: Int,
}

pub type VaultRedeemer {
  Deposit { tranche: Tranche, depositor: VerificationKeyHash }
  Withdraw { tranche: Tranche, shares: Int }
  UpdateConfig { config: VaultConfig }
  Disburse {
    principal: Int,
    borrower: VerificationKeyHash,
    revenue_share_bps: Int,
    repayment_cap: Int,
    loan_asset_name: AssetName,
  }
}

pub type WhitelistRedeemer {
  MintKyc { holder: VerificationKeyHash }
  BurnKyc { holder: VerificationKeyHash }
}

pub type OpenLoanRedeemer {
  borrower: VerificationKeyHash,
  principal: Int,
  revenue_share_bps: Int,
  repayment_cap: Int,
  loan_asset_name: AssetName,
}

pub type CreditSpendRedeemer {
  Repay { principal_paid: Int, interest_paid: Int }
}

pub type ShareMintRedeemer {
  senior_delta: Int,
  junior_delta: Int,
}

pub type LoanStatus {
  PendingDisburse
  Active
  Repaid
  Defaulted
}

pub type LoanDatum {
  credit_script: ScriptHash,
  borrower: VerificationKeyHash,
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

pub fn tranche_shares(datum: VaultDatum, tranche: Tranche) -> Int {
  when tranche is {
    Senior -> datum.senior_shares
    Junior -> datum.junior_shares
  }
}

pub fn tranche_assets(datum: VaultDatum, tranche: Tranche) -> Int {
  when tranche is {
    Senior -> datum.senior_assets
    Junior -> datum.junior_assets
  }
}

pub fn with_tranche_shares(
  datum: VaultDatum,
  tranche: Tranche,
  shares: Int,
) -> VaultDatum {
  when tranche is {
    Senior -> VaultDatum { ..datum, senior_shares: shares }
    Junior -> VaultDatum { ..datum, junior_shares: shares }
  }
}

pub fn with_tranche_assets(
  datum: VaultDatum,
  tranche: Tranche,
  assets: Int,
) -> VaultDatum {
  when tranche is {
    Senior -> VaultDatum { ..datum, senior_assets: assets }
    Junior -> VaultDatum { ..datum, junior_assets: assets }
  }
}
