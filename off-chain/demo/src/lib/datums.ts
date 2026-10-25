import { Data } from "@lucid-evolution/lucid";
import { allocateInterest, vaultRepayUsdcxDelta } from "./waterfall.js";

const VerificationKeyHash = Data.Bytes();
const PolicyId = Data.Bytes();
const ScriptHash = Data.Bytes();

export const VaultConfigSchema = Data.Object({
  max_single_borrower_bps: Data.Integer(),
  protocol_fee_bps: Data.Integer(),
  curator_fee_bps: Data.Integer(),
  senior_rate_bps: Data.Integer(),
  attester: VerificationKeyHash,
  protocol_treasury: VerificationKeyHash,
});

export const VaultDatumSchema = Data.Object({
  curator: VerificationKeyHash,
  usdcx_policy: PolicyId,
  whitelist_policy: PolicyId,
  share_policy: PolicyId,
  credit_script: ScriptHash,
  config: VaultConfigSchema,
  senior_shares: Data.Integer(),
  junior_shares: Data.Integer(),
  senior_assets: Data.Integer(),
  junior_assets: Data.Integer(),
  deployed_outstanding: Data.Integer(),
});

export type VaultConfig = Data.Static<typeof VaultConfigSchema>;
export type VaultDatum = Data.Static<typeof VaultDatumSchema>;

export function encodeVaultDatum(datum: VaultDatum): string {
  return Data.to(VaultDatumSchema as never, datum as never);
}

/** First senior deposit when tranche is empty: 1:1 shares (matches shares.ak). */
export function afterFirstSeniorDeposit(
  datum: VaultDatum,
  deposit: bigint,
): VaultDatum {
  return {
    ...datum,
    senior_shares: datum.senior_shares + deposit,
    senior_assets: datum.senior_assets + deposit,
  };
}

export function applyRepayVaultDatum(
  datum: VaultDatum,
  principalPaid: bigint,
  interestPaid: bigint,
): VaultDatum {
  if (principalPaid <= 0n && interestPaid <= 0n) {
    throw new Error("Repay requires positive principal and/or interest");
  }
  if (principalPaid > datum.deployed_outstanding) {
    throw new Error("principal_paid exceeds deployed_outstanding");
  }
  const alloc = allocateInterest(
    interestPaid,
    datum.config.protocol_fee_bps,
    datum.config.curator_fee_bps,
    datum.config.senior_rate_bps,
  );
  return {
    ...datum,
    deployed_outstanding: datum.deployed_outstanding - principalPaid,
    senior_assets: datum.senior_assets + alloc.seniorInterest,
    junior_assets: datum.junior_assets + alloc.juniorInterest,
  };
}

export { vaultRepayUsdcxDelta };

export function defaultVaultDatum(args: {
  curator: string;
  usdcxPolicy: string;
  whitelistPolicy: string;
  sharePolicy: string;
  creditScript: string;
  attesterVkh: string;
  protocolTreasuryVkh: string;
}): VaultDatum {
  return {
    curator: args.curator,
    usdcx_policy: args.usdcxPolicy,
    whitelist_policy: args.whitelistPolicy,
    share_policy: args.sharePolicy,
    credit_script: args.creditScript,
    config: {
      max_single_borrower_bps: 1_000n,
      protocol_fee_bps: 200n,
      curator_fee_bps: 1_000n,
      senior_rate_bps: 8_000n,
      attester: args.attesterVkh,
      protocol_treasury: args.protocolTreasuryVkh,
    },
    senior_shares: 0n,
    junior_shares: 0n,
    senior_assets: 0n,
    junior_assets: 0n,
    deployed_outstanding: 0n,
  };
}
