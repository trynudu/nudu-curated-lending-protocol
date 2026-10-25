import { fromText, getAddressDetails } from "@lucid-evolution/lucid";
import { USDCX_ASSET_NAME } from "../lib/constants.js";
import { VaultDatumSchema, encodeVaultDatum } from "../lib/datums.js";
import { Data } from "@lucid-evolution/lucid";
import { readDeployment } from "../lib/deployment.js";
import { encodeOpenLoanDatum, encodeOpenLoanMintRedeemer } from "../lib/loan-datum.js";
import { lucidFromEnvRole } from "../lib/lucid.js";
import { vaultDisburseRedeemer } from "../lib/redeemers.js";
import { scriptsForDeployment } from "../lib/scripts-from-deployment.js";
import { payWithInlineDatum } from "../lib/tx-pay.js";
import type { VaultDatum } from "../lib/datums.js";

async function main() {
  const d = readDeployment();
  const lucid = await lucidFromEnvRole("CURATOR");
  const borrowerLucid = await lucidFromEnvRole("BORROWER");
  const borrowerAddr = await borrowerLucid.wallet().address();
  const borrowerVkh =
    getAddressDetails(borrowerAddr).paymentCredential?.hash ?? d.roles.borrowerVkh;
  const principal = BigInt(process.env.PRINCIPAL ?? "500000");
  const revenueShareBps = BigInt(process.env.REVENUE_SHARE_BPS ?? "500");
  const repaymentCap = BigInt(process.env.REPAYMENT_CAP ?? "2000000");
  const loanAssetNameHex = process.env.LOAN_ASSET_NAME_HEX ?? fromText("loan1");
  const { vault, credit } = scriptsForDeployment(d);
  const vaultUtxos = await lucid.utxosAt(d.scripts.vaultAddress);
  if (vaultUtxos.length === 0) {
    throw new Error("No vault UTxO");
  }
  const vaultUtxo = vaultUtxos[0];
  if (!vaultUtxo.datum) {
    throw new Error("Vault UTxO missing inline datum");
  }
  const currentDatum = Data.from(
    vaultUtxo.datum,
    VaultDatumSchema as never,
  ) as VaultDatum;
  const nextDatum = {
    ...currentDatum,
    deployed_outstanding: currentDatum.deployed_outstanding + principal,
  };
  const usdcxUnit = d.assets.usdcxPolicyId + USDCX_ASSET_NAME;
  const inUsdcx = vaultUtxo.assets[usdcxUnit] ?? 0n;
  if (inUsdcx < principal) {
    throw new Error("Vault lacks pilot USDCx for disburse");
  }
  const loanUnit = d.scripts.creditHash + loanAssetNameHex;
  const disburseRedeemer = vaultDisburseRedeemer({
    principal,
    borrower: borrowerVkh,
    revenueShareBps,
    repaymentCap,
    loanAssetNameHex,
  });
  const openMint = encodeOpenLoanMintRedeemer({
    vaultScript: d.scripts.vaultHash,
    borrower: borrowerVkh,
    principal,
    revenueShareBps,
    repaymentCap,
    loanAssetNameHex,
  });
  const loanDatum = encodeOpenLoanDatum({
    vaultScript: d.scripts.vaultHash,
    creditScript: d.scripts.creditHash,
    borrower: borrowerVkh,
    principal,
    revenueShareBps,
    repaymentCap,
  });
  let builder = lucid
    .newTx()
    .collectFrom([vaultUtxo], disburseRedeemer)
    .attach.SpendingValidator(vault)
    .mintAssets({ [loanUnit]: 1n }, openMint)
    .attach.MintingPolicy(credit)
    .pay.ToAddress(borrowerAddr, { [usdcxUnit]: principal });
  builder = payWithInlineDatum(
    builder,
    d.scripts.vaultAddress,
    {
      lovelace: (vaultUtxo.assets.lovelace ?? 0n) + 2_000_000n,
      [usdcxUnit]: inUsdcx - principal,
    },
    encodeVaultDatum(nextDatum),
  );
  builder = payWithInlineDatum(
    builder,
    d.scripts.creditAddress,
    { lovelace: 3_000_000n, [loanUnit]: 1n },
    loanDatum,
  );
  const tx = await builder.complete();
  const signed = await tx.sign.withWallet().complete();
  const hash = await signed.submit();
  await lucid.awaitTx(hash);
  console.log(`Disburse + open loan tx: ${hash}`);
  console.log(`Loan unit: ${loanUnit}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
