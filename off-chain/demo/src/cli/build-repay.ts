import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { Data, credentialToAddress, getAddressDetails } from "@lucid-evolution/lucid";
import { USDCX_ASSET_NAME } from "../lib/constants.js";
import {
  VaultDatumSchema,
  applyRepayVaultDatum,
  encodeVaultDatum,
  vaultRepayUsdcxDelta,
} from "../lib/datums.js";
import { readDeployment } from "../lib/deployment.js";
import {
  LoanDatumSchema,
  applyLoanRepay,
  encodeLoanDatum,
} from "../lib/loan-datum.js";
import { lucidFromEnvRole } from "../lib/lucid.js";
import { repoRoot } from "../lib/paths.js";
import {
  creditRepayRedeemer,
  revenueAttestationConstr,
  vaultRecordRepaymentRedeemer,
} from "../lib/redeemers.js";
import { scriptsForDeployment } from "../lib/scripts-from-deployment.js";
import { payWithInlineDatum } from "../lib/tx-pay.js";
import { allocateInterest } from "../lib/waterfall.js";
import type { VaultDatum } from "../lib/datums.js";
import type { LoanDatum } from "../lib/loan-datum.js";

type SignOut = {
  verification_key: string;
  verification_key_hash: string;
  signature: string;
};

function signAttestationJson(
  attestation: Record<string, number | string>,
  seedFile: string,
): SignOut {
  const tmp = path.join(repoRoot, "off-chain/demo/.attestation-input.json");
  fs.writeFileSync(tmp, JSON.stringify(attestation));
  const out = execFileSync(
    "python3",
    [
      path.join(repoRoot, "scripts/sign_attestation.py"),
      "--input",
      tmp,
      "--seed-file",
      seedFile,
    ],
    { encoding: "utf8" },
  );
  return JSON.parse(out) as SignOut;
}

function vkhAddress(
  network: "Preprod" | "Mainnet",
  vkh: string,
): string {
  return credentialToAddress(network, { type: "Key", hash: vkh });
}

async function main() {
  const d = readDeployment();
  const lucid = await lucidFromEnvRole("BORROWER");
  const network = d.network;
  const principalPaid = BigInt(process.env.PRINCIPAL_PAID ?? "500");
  const interestPaid = BigInt(process.env.INTEREST_PAID ?? "10000");
  const loanTxId = process.env.LOAN_TX_ID ?? "";
  const loanOutputIndex = BigInt(process.env.LOAN_OUTPUT_INDEX ?? "0");
  const loanAssetNameHex = process.env.LOAN_ASSET_NAME_HEX ?? "";
  if (!loanTxId) {
    throw new Error("Set LOAN_TX_ID (hex) from the loan UTxO on preprod.");
  }
  const seedFile = process.env.ATTESTER_SIGNING_SEED_FILE;
  if (!seedFile) {
    throw new Error("Set ATTESTER_SIGNING_SEED_FILE");
  }
  const validUntil = BigInt(process.env.VALID_UNTIL ?? "4102444800000");
  const attestationFields = {
    loan_tx_id: loanTxId,
    loan_output_index: Number(loanOutputIndex),
    period_id: Number(process.env.PERIOD_ID ?? "202601"),
    attested_revenue: Number(process.env.ATTESTED_REVENUE ?? "500000"),
    principal_paid: Number(principalPaid),
    interest_paid: Number(interestPaid),
    valid_until: Number(validUntil),
    nonce: Number(process.env.ATTESTATION_NONCE ?? "1"),
  };
  const signed = signAttestationJson(attestationFields, seedFile);
  if (signed.verification_key_hash !== d.roles.attesterVkh) {
    throw new Error(
      `Attester vkh mismatch: deployment ${d.roles.attesterVkh} vs seed ${signed.verification_key_hash}`,
    );
  }

  const { vault, credit } = scriptsForDeployment(d);
  const usdcxUnit = d.assets.usdcxPolicyId + USDCX_ASSET_NAME;
  const vaultUtxos = await lucid.utxosAt(d.scripts.vaultAddress);
  if (vaultUtxos.length === 0) {
    throw new Error("No vault UTxO");
  }
  const vaultUtxo = vaultUtxos[0];
  if (!vaultUtxo.datum) {
    throw new Error("Vault UTxO missing datum");
  }
  const vaultIn = Data.from(
    vaultUtxo.datum,
    VaultDatumSchema as never,
  ) as VaultDatum;
  const vaultOut = applyRepayVaultDatum(vaultIn, principalPaid, interestPaid);
  const alloc = allocateInterest(
    interestPaid,
    vaultIn.config.protocol_fee_bps,
    vaultIn.config.curator_fee_bps,
    vaultIn.config.senior_rate_bps,
  );
  const vaultInUsdcx = vaultUtxo.assets[usdcxUnit] ?? 0n;
  const delta = vaultRepayUsdcxDelta(principalPaid, interestPaid, alloc);
  const vaultOutUsdcx = vaultInUsdcx + delta;

  let loanUtxo =
    loanAssetNameHex.length > 0
      ? await lucid.utxoByUnit(d.scripts.creditHash + loanAssetNameHex)
      : undefined;
  if (!loanUtxo) {
    const idx = Number(loanOutputIndex);
    const candidates = await lucid.utxosAt(d.scripts.creditAddress);
    loanUtxo = candidates.find(
      (u) => u.txHash === loanTxId && u.outputIndex === idx,
    );
  }
  if (!loanUtxo?.datum) {
    throw new Error("Loan UTxO not found or missing inline datum");
  }
  const loanIn = Data.from(
    loanUtxo.datum,
    LoanDatumSchema as never,
  ) as LoanDatum;
  const loanOut = applyLoanRepay(loanIn, principalPaid, interestPaid);

  const attestation = revenueAttestationConstr({
    loanTxId,
    loanOutputIndex,
    periodId: BigInt(attestationFields.period_id),
    attestedRevenue: BigInt(attestationFields.attested_revenue),
    principalPaid,
    interestPaid,
    validUntil,
    nonce: BigInt(attestationFields.nonce),
  });
  const creditRedeemer = creditRepayRedeemer({
    principalPaid,
    interestPaid,
    attestation,
    attesterVkey: signed.verification_key,
    attesterSignature: signed.signature,
  });
  const vaultRedeemer = vaultRecordRepaymentRedeemer(principalPaid, interestPaid);

  const treasuryAddr = vkhAddress(network, vaultIn.config.protocol_treasury);
  const curatorAddr = vkhAddress(network, vaultIn.curator);

  const loanAssetUnit = Object.keys(loanUtxo.assets).find(
    (unit) => unit !== "lovelace" && unit.startsWith(d.scripts.creditHash),
  );
  if (!loanAssetUnit) {
    throw new Error("Loan UTxO missing credit policy token");
  }

  const paymentTotal = principalPaid + interestPaid;
  const walletUsdcx = (await lucid.wallet().getUtxos()).reduce(
    (acc, u) => acc + (u.assets[usdcxUnit] ?? 0n),
    0n,
  );
  if (walletUsdcx < paymentTotal) {
    throw new Error(
      `Borrower needs at least ${paymentTotal} pilot USDCx; wallet has ${walletUsdcx}`,
    );
  }

  let tx = lucid
    .newTx()
    .collectFrom([vaultUtxo], vaultRedeemer)
    .attach.SpendingValidator(vault)
    .collectFrom([loanUtxo], creditRedeemer)
    .attach.SpendingValidator(credit);
  tx = payWithInlineDatum(
    tx,
    d.scripts.vaultAddress,
    {
      lovelace: (vaultUtxo.assets.lovelace ?? 0n) + 2_000_000n,
      [usdcxUnit]: vaultOutUsdcx,
    },
    encodeVaultDatum(vaultOut),
  );
  tx = payWithInlineDatum(
    tx,
    d.scripts.creditAddress,
    {
      lovelace: (loanUtxo.assets.lovelace ?? 0n) + 2_000_000n,
      [loanAssetUnit]: 1n,
    },
    encodeLoanDatum(loanOut),
  );

  if (alloc.protocolFee > 0n) {
    tx = tx.pay.ToAddress(treasuryAddr, { [usdcxUnit]: alloc.protocolFee });
  }
  if (alloc.curatorFee > 0n) {
    tx = tx.pay.ToAddress(curatorAddr, { [usdcxUnit]: alloc.curatorFee });
  }

  const borrowerVkh =
    getAddressDetails(await lucid.wallet().address()).paymentCredential?.hash;
  if (borrowerVkh !== loanIn.borrower) {
    throw new Error("BORROWER_SEED_FILE does not match loan borrower vkh");
  }

  const completed = await tx
    .validTo(Number(validUntil))
    .complete({ changeAddress: await lucid.wallet().address() });

  const signedTx = await completed.sign.withWallet().complete();
  const hash = await signedTx.submit();
  await lucid.awaitTx(hash);
  console.log(`Repay tx: ${hash}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
