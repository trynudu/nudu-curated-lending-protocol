import { Data } from "@lucid-evolution/lucid";
import { SENIOR_SHARE_NAME, USDCX_ASSET_NAME } from "../lib/constants.js";
import {
  VaultDatumSchema,
  afterFirstSeniorDeposit,
  encodeVaultDatum,
} from "../lib/datums.js";
import { readDeployment } from "../lib/deployment.js";
import { lucidFromEnvRole } from "../lib/lucid.js";
import { shareMintRedeemer, vaultDepositRedeemer } from "../lib/redeemers.js";
import { scriptsForDeployment } from "../lib/scripts-from-deployment.js";
import { payWithInlineDatum } from "../lib/tx-pay.js";
import type { VaultDatum } from "../lib/datums.js";

async function main() {
  const d = readDeployment();
  const lucid = await lucidFromEnvRole("LP");
  const { vault, share } = scriptsForDeployment(d);
  const depositAmount = BigInt(process.env.DEPOSIT_USDCX ?? "1000000");
  const usdcxUnit = d.assets.usdcxPolicyId + USDCX_ASSET_NAME;
  const vaultUtxos = await lucid.utxosAt(d.scripts.vaultAddress);
  if (vaultUtxos.length === 0) {
    throw new Error("No vault UTxO — run init:vault first.");
  }
  const vaultUtxo = vaultUtxos[0];
  if (!vaultUtxo.datum) {
    throw new Error("Vault UTxO missing datum");
  }
  const currentDatum = Data.from(
    vaultUtxo.datum,
    VaultDatumSchema as never,
  ) as VaultDatum;
  const nextDatum = afterFirstSeniorDeposit(currentDatum, depositAmount);
  const redeemer = vaultDepositRedeemer(true, d.roles.lpVkh);
  const seniorUnit = d.scripts.sharePolicyId + SENIOR_SHARE_NAME;
  const shareRedeemer = shareMintRedeemer(depositAmount, 0n);
  let builder = lucid
    .newTx()
    .collectFrom([vaultUtxo], redeemer)
    .attach.SpendingValidator(vault)
    .mintAssets({ [seniorUnit]: depositAmount }, shareRedeemer)
    .attach.MintingPolicy(share);
  builder = payWithInlineDatum(
    builder,
    d.scripts.vaultAddress,
    {
      lovelace: (vaultUtxo.assets.lovelace ?? 0n) + 2_000_000n,
      [usdcxUnit]: depositAmount,
    },
    encodeVaultDatum(nextDatum),
  );
  const tx = await builder.complete();
  const signed = await tx.sign.withWallet().complete();
  const hash = await signed.submit();
  await lucid.awaitTx(hash);
  console.log(`Senior deposit tx: ${hash}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
