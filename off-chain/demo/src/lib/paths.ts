import { fileURLToPath } from "node:url";
import path from "node:path";

const demoRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
export const repoRoot = path.resolve(demoRoot, "../..");
export const blueprintPath = path.join(repoRoot, "blueprint/plutus.json");
export const deploymentPath = path.join(demoRoot, "deployment.json");
export const pilotUsdcxPath = path.join(demoRoot, "pilot-usdcx.json");
