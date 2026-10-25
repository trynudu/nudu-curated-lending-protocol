import fs from "node:fs";
import {
  applyValidator,
  loadBlueprint,
  resolveCreditScript,
  scriptAddress,
  scriptHash,
} from "./blueprint.js";
import { deploymentPath } from "./paths.js";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { repoRoot } from "./paths.js";

export type Deployment = {
  network: "Preprod" | "Mainnet";
  generatedAt: string;
  roles: {
    curatorVkh: string;
    lpVkh: string;
    borrowerVkh: string;
    attesterVkh: string;
    attesterVkey: string;
  };
  scripts: {
    vaultHash: string;
    vaultAddress: string;
    creditHash: string;
    creditAddress: string;
    sharePolicyId: string;
    whitelistPolicyId: string;
  };
  assets: {
    usdcxPolicyId: string;
    usdcxAssetNameHex: string;
  };
};

export function attesterFromSeedFile(seedFile: string): {
  vkh: string;
  vkey: string;
} {
  const script = path.join(repoRoot, "scripts/attester_credentials.py");
  const out = execFileSync("python3", [script, seedFile], { encoding: "utf8" });
  const json = JSON.parse(out) as {
    verification_key: string;
    verification_key_hash: string;
  };
  return { vkey: json.verification_key, vkh: json.verification_key_hash };
}

export function buildDeployment(args: {
  network: "Preprod" | "Mainnet";
  curatorVkh: string;
  lpVkh: string;
  borrowerVkh: string;
  attesterSeedFile: string;
  usdcxPolicyId: string;
  protocolTreasuryVkh: string;
}): Deployment {
  const blueprint = loadBlueprint();
  const attester = attesterFromSeedFile(args.attesterSeedFile);
  const vault = applyValidator(blueprint, "vault.vault.spend", []);
  const credit = resolveCreditScript(blueprint, args.curatorVkh);
  const share = applyValidator(blueprint, "share_policy.share_policy.mint", []);
  const whitelist = applyValidator(blueprint, "whitelist_policy.whitelist_policy.mint", [
    args.curatorVkh,
  ]);

  return {
    network: args.network,
    generatedAt: new Date().toISOString(),
    roles: {
      curatorVkh: args.curatorVkh,
      lpVkh: args.lpVkh,
      borrowerVkh: args.borrowerVkh,
      attesterVkh: attester.vkh,
      attesterVkey: attester.vkey,
    },
    scripts: {
      vaultHash: scriptHash(vault),
      vaultAddress: scriptAddress(vault, args.network),
      creditHash: scriptHash(credit),
      creditAddress: scriptAddress(credit, args.network),
      sharePolicyId: scriptHash(share),
      whitelistPolicyId: scriptHash(whitelist),
    },
    assets: {
      usdcxPolicyId: args.usdcxPolicyId,
      usdcxAssetNameHex: "",
    },
  };
}

export function writeDeployment(d: Deployment): void {
  fs.writeFileSync(deploymentPath, JSON.stringify(d, null, 2));
}

export function readDeployment(): Deployment {
  return JSON.parse(fs.readFileSync(deploymentPath, "utf8")) as Deployment;
}
