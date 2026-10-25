import { applyValidator, loadBlueprint, resolveCreditScript } from "./blueprint.js";
import type { Deployment } from "./deployment.js";

export function scriptsForDeployment(d: Deployment) {
  const blueprint = loadBlueprint();
  const vault = applyValidator(blueprint, "vault.vault.spend", []);
  const credit = resolveCreditScript(blueprint, d.roles.curatorVkh);
  const share = applyValidator(blueprint, "share_policy.share_policy.mint", []);
  const whitelist = applyValidator(
    blueprint,
    "whitelist_policy.whitelist_policy.mint",
    [d.roles.curatorVkh],
  );
  return { vault, credit, share, whitelist };
}
