import {
  getAddressDetails,
  mintingPolicyToId,
  scriptFromNative,
} from "@lucid-evolution/lucid";
import fs from "node:fs";
import { USDCX_ASSET_NAME } from "../lib/constants.js";
import { lucidFromEnvRole } from "../lib/lucid.js";
import { pilotUsdcxPath } from "../lib/paths.js";

/** Curator-gated one-shot mint policy for demo “USDCx” on preprod. */
async function main() {
  const lucid = await lucidFromEnvRole("CURATOR");
  const addr = await lucid.wallet().address();
  const curatorVkh = getAddressDetails(addr).paymentCredential?.hash;
  if (!curatorVkh) {
    throw new Error("Curator payment credential required.");
  }
  const policy = scriptFromNative({ type: "sig", keyHash: curatorVkh });
  const policyId = mintingPolicyToId(policy);
  const mintAmount = BigInt(process.env.PILOT_USDCX_MINT ?? "1000000000");
  const tx = await lucid
    .newTx()
    .mintAssets({ [policyId + USDCX_ASSET_NAME]: mintAmount })
    .attach.MintingPolicy(policy)
    .complete();
  const signed = await tx.sign.withWallet().complete();
  const hash = await signed.submit();
  await lucid.awaitTx(hash);
  fs.writeFileSync(
    pilotUsdcxPath,
    JSON.stringify({ policyId, mintTx: hash, mintAmount: mintAmount.toString() }, null, 2),
  );
  console.log(`Pilot USDCx policy ${policyId}, mint tx ${hash}`);
}

/** Plutus Data void redeemer for native mint (unused body). */
function DataVoid(): string {
  return "d87980";
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
