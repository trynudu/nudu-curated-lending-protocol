import { Constr, Data } from "@lucid-evolution/lucid";

/** Tranche: Senior = 0, Junior = 1 (matches lib/types.ak order). */
export function trancheSenior(): Constr<[]> {
  return new Constr(0, []);
}

export function trancheJunior(): Constr<[]> {
  return new Constr(1, []);
}

export function vaultDepositRedeemer(
  senior: boolean,
  depositorVkh: string,
): string {
  const tranche = senior ? trancheSenior() : trancheJunior();
  const redeemer = new Constr(0, [tranche, depositorVkh]);
  return Data.to(redeemer);
}

export function whitelistMintKycRedeemer(holderVkh: string): string {
  const redeemer = new Constr(0, [holderVkh]);
  return Data.to(redeemer);
}

export function shareMintRedeemer(seniorDelta: bigint, juniorDelta: bigint): string {
  const redeemer = new Constr(0, [seniorDelta, juniorDelta]);
  return Data.to(redeemer);
}

export function vaultRecordRepaymentRedeemer(
  principalPaid: bigint,
  interestPaid: bigint,
): string {
  const redeemer = new Constr(4, [principalPaid, interestPaid]);
  return Data.to(redeemer);
}

export function creditRepayRedeemer(args: {
  principalPaid: bigint;
  interestPaid: bigint;
  attestation: Constr<unknown>;
  attesterVkey: string;
  attesterSignature: string;
}): string {
  const redeemer = new Constr(0, [
    args.principalPaid,
    args.interestPaid,
    args.attestation,
    args.attesterVkey,
    args.attesterSignature,
  ]);
  return Data.to(redeemer as never);
}

export function revenueAttestationConstr(args: {
  loanTxId: string;
  loanOutputIndex: bigint;
  periodId: bigint;
  attestedRevenue: bigint;
  principalPaid: bigint;
  interestPaid: bigint;
  validUntil: bigint;
  nonce: bigint;
}): Constr<unknown> {
  const loanRef = new Constr(0, [args.loanTxId, args.loanOutputIndex]);
  return new Constr(0, [
    loanRef,
    args.periodId,
    args.attestedRevenue,
    args.principalPaid,
    args.interestPaid,
    args.validUntil,
    args.nonce,
  ]);
}

export function vaultDisburseRedeemer(args: {
  principal: bigint;
  borrower: string;
  revenueShareBps: bigint;
  repaymentCap: bigint;
  loanAssetNameHex: string;
}): string {
  const redeemer = new Constr(3, [
    args.principal,
    args.borrower,
    args.revenueShareBps,
    args.repaymentCap,
    args.loanAssetNameHex,
  ]);
  return Data.to(redeemer);
}
