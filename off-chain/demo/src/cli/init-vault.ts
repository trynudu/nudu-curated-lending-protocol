import { WHITELIST_ASSET_NAME } from "../lib/constants.js";
import { defaultVaultDatum, encodeVaultDatum } from "../lib/datums.js";
import { readDeployment } from "../lib/deployment.js";
import { lucidFromEnvRole } from "../lib/lucid.js";
import { whitelistMintKycRedeemer } from "../lib/redeemers.js";
import { scriptsForDeployment } from "../lib/scripts-from-deployment.js";

async function main() {
  const d = readDeployment();
  const lucid = await lucidFromEnvRole("CURATOR");
  const { vault, whitelist } = scriptsForDeployment(d);
  const lpLucid = await lucidFromEnvRole("LP");
  const lpAddr = await lpLucid.wallet().address();
  const lpVkh = d.roles.lpVkh;
  const datum = defaultVaultDatum({
    curator: d.roles.curatorVkh,
    usdcxPolicy: d.assets.usdcxPolicyId,
    whitelistPolicy: d.scripts.whitelistPolicyId,
    sharePolicy: d.scripts.sharePolicyId,
    creditScript: d.scripts.creditHash,
    attesterVkh: d.roles.attesterVkh,
    protocolTreasuryVkh: d.roles.curatorVkh,
  });
  const kycUnit = d.scripts.whitelistPolicyId + WHITELIST_ASSET_NAME;
  const mintRedeemer = whitelistMintKycRedeemer(lpVkh);
  const tx = await lucid
    .newTx()
    .mintAssets({ [kycUnit]: 1n }, mintRedeemer)
    .attach.MintingPolicy(whitelist)
    .pay.ToAddress(lpAddr, { [kycUnit]: 1n })
    .pay.ToAddressWithData(
      d.scripts.vaultAddress,
      { kind: "inline", value: encodeVaultDatum(datum) },
      { lovelace: 5_000_000n },
    )
    .complete();
  const signed = await tx.sign.withWallet().complete();
  const hash = await signed.submit();
  await lucid.awaitTx(hash);
  console.log(`Init vault + KYC mint tx: ${hash}`);
  console.log(`Vault address: ${d.scripts.vaultAddress}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
