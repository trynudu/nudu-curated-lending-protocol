import { Constr, Data } from "@lucid-evolution/lucid";

const VerificationKeyHash = Data.Bytes();
const ScriptHash = Data.Bytes();

/** LoanStatus Active (lib/types.ak). */
function loanStatusActive(): Constr<[]> {
  return new Constr(1, []);
}

export const LoanDatumSchema = Data.Object({
  vault_script: ScriptHash,
  credit_script: ScriptHash,
  borrower: VerificationKeyHash,
  principal: Data.Integer(),
  outstanding_principal: Data.Integer(),
  revenue_share_bps: Data.Integer(),
  repayment_cap: Data.Integer(),
  total_repaid: Data.Integer(),
  status: Data.Any(),
});

export type LoanDatum = Data.Static<typeof LoanDatumSchema>;

export function encodeLoanDatum(datum: LoanDatum): string {
  return Data.to(LoanDatumSchema as never, datum as never);
}

export function applyLoanRepay(
  loan: LoanDatum,
  principalPaid: bigint,
  interestPaid: bigint,
): LoanDatum {
  if (principalPaid < 0n || principalPaid > loan.outstanding_principal) {
    throw new Error("principal_paid out of range");
  }
  if (principalPaid === 0n && interestPaid <= 0n) {
    throw new Error("Repay payment must be positive");
  }
  const remaining = loan.outstanding_principal - principalPaid;
  const paymentTotal = principalPaid + interestPaid;
  return {
    ...loan,
    outstanding_principal: remaining,
    total_repaid: loan.total_repaid + paymentTotal,
    status: remaining === 0n ? new Constr(2, []) : loan.status,
  };
}

export function encodeOpenLoanDatum(args: {
  vaultScript: string;
  creditScript: string;
  borrower: string;
  principal: bigint;
  revenueShareBps: bigint;
  repaymentCap: bigint;
}): string {
  const loan = new Constr(0, [
    args.vaultScript,
    args.creditScript,
    args.borrower,
    args.principal,
    args.principal,
    args.revenueShareBps,
    args.repaymentCap,
    0n,
    loanStatusActive(),
  ]);
  return Data.to(loan);
}

export function encodeOpenLoanMintRedeemer(args: {
  vaultScript: string;
  borrower: string;
  principal: bigint;
  revenueShareBps: bigint;
  repaymentCap: bigint;
  loanAssetNameHex: string;
}): string {
  const redeemer = new Constr(0, [
    args.vaultScript,
    args.borrower,
    args.principal,
    args.revenueShareBps,
    args.repaymentCap,
    args.loanAssetNameHex,
  ]);
  return Data.to(redeemer);
}
