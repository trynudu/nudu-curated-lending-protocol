import { getAddressDetails } from "@lucid-evolution/lucid";
import fs from "node:fs";
import {
  buildDeployment,
  writeDeployment,
} from "../lib/deployment.js";
import { lucidFromEnvRole } from "../lib/lucid.js";
import { networkFromEnv } from "../lib/lucid.js";
import { pilotUsdcxPath } from "../lib/paths.js";

async function main() {
  const network = networkFromEnv();
  const curator = await lucidFromEnvRole("CURATOR");
  const lp = await lucidFromEnvRole("LP");
  const borrower = await lucidFromEnvRole("BORROWER");
  const curatorVkh = getAddressDetails(await curator.wallet().address()).paymentCredential
    ?.hash;
  const lpVkh = getAddressDetails(await lp.wallet().address()).paymentCredential?.hash;
  const borrowerVkh = getAddressDetails(await borrower.wallet().address()).paymentCredential
    ?.hash;
  if (!curatorVkh || !lpVkh || !borrowerVkh) {
    throw new Error("Could not resolve payment key hashes for demo wallets.");
  }
  const attesterSeed = process.env.ATTESTER_SIGNING_SEED_FILE;
  if (!attesterSeed) {
    throw new Error("Set ATTESTER_SIGNING_SEED_FILE (32-byte raw attester seed).");
  }
  let usdcxPolicyId = process.env.PILOT_USDCX_POLICY_ID ?? "";
  if (!usdcxPolicyId && fs.existsSync(pilotUsdcxPath)) {
    usdcxPolicyId = (JSON.parse(fs.readFileSync(pilotUsdcxPath, "utf8")) as {
      policyId: string;
    }).policyId;
  }
  if (!usdcxPolicyId) {
    throw new Error(
      "Run npm run mint:pilot-usdcx first or set PILOT_USDCX_POLICY_ID / pilot-usdcx.json",
    );
  }
  const deployment = buildDeployment({
    network,
    curatorVkh,
    lpVkh,
    borrowerVkh,
    attesterSeedFile: attesterSeed,
    usdcxPolicyId,
    protocolTreasuryVkh: curatorVkh,
  });
  writeDeployment(deployment);
  console.log(JSON.stringify(deployment, null, 2));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
