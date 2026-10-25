import fs from "node:fs";
import { USDCX_ASSET_NAME } from "../lib/constants.js";
import { lucidFromEnvRole } from "../lib/lucid.js";
import { pilotUsdcxPath } from "../lib/paths.js";

/** Send pilot USDCx from curator to LP and borrower (after mint:pilot-usdcx). */
async function main() {
  if (!fs.existsSync(pilotUsdcxPath)) {
    throw new Error("Run npm run mint:pilot-usdcx first.");
  }
  const { policyId } = JSON.parse(fs.readFileSync(pilotUsdcxPath, "utf8")) as {
    policyId: string;
  };
  const unit = policyId + USDCX_ASSET_NAME;
  const each = BigInt(process.env.PILOT_USDCX_SPLIT ?? "100000000");
  const curator = await lucidFromEnvRole("CURATOR");
  const lpAddr = await (await lucidFromEnvRole("LP")).wallet().address();
  const borrowerAddr = await (await lucidFromEnvRole("BORROWER")).wallet().address();
  const tx = await curator
    .newTx()
    .pay.ToAddress(lpAddr, { [unit]: each })
    .pay.ToAddress(borrowerAddr, { [unit]: each })
    .complete();
  const signed = await tx.sign.withWallet().complete();
  const hash = await signed.submit();
  await curator.awaitTx(hash);
  console.log(`Funded LP + borrower with ${each} pilot USDCx each (tx ${hash})`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
