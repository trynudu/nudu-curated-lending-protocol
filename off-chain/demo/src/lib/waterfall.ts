/** Mirrors lib/waterfall.ak allocate_interest (integer math). */
const BPS = 10_000n;

export type WaterfallAllocation = {
  protocolFee: bigint;
  curatorFee: bigint;
  seniorInterest: bigint;
  juniorInterest: bigint;
};

export function allocateInterest(
  interestPaid: bigint,
  protocolFeeBps: bigint,
  curatorFeeBps: bigint,
  seniorRateBps: bigint,
): WaterfallAllocation {
  if (interestPaid <= 0n) {
    return {
      protocolFee: 0n,
      curatorFee: 0n,
      seniorInterest: 0n,
      juniorInterest: 0n,
    };
  }
  const protocolFee = (interestPaid * protocolFeeBps) / BPS;
  const afterProtocol = interestPaid - protocolFee;
  const curatorFee = (afterProtocol * curatorFeeBps) / BPS;
  const afterCurator = afterProtocol - curatorFee;
  const seniorInterest = (afterCurator * seniorRateBps) / BPS;
  const juniorInterest = afterCurator - seniorInterest;
  return { protocolFee, curatorFee, seniorInterest, juniorInterest };
}

export function vaultRepayUsdcxDelta(
  principalPaid: bigint,
  interestPaid: bigint,
  alloc: WaterfallAllocation,
): bigint {
  return principalPaid + interestPaid - alloc.protocolFee - alloc.curatorFee;
}
