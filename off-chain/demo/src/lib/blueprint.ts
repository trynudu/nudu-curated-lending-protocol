import fs from "node:fs";
import {
  applyParamsToScript,
  validatorToAddress,
  validatorToScriptHash,
  type Network,
  type Script,
} from "@lucid-evolution/lucid";
import { blueprintPath } from "./paths.js";

export type BlueprintValidator = {
  title: string;
  compiledCode: string;
};

export type Blueprint = {
  validators: BlueprintValidator[];
};

export function loadBlueprint(): Blueprint {
  if (!fs.existsSync(blueprintPath)) {
    throw new Error(
      `Missing ${blueprintPath}. Run ../../scripts/fetch-plutus-blueprint.sh or aiken build -o blueprint/plutus.json`,
    );
  }
  return JSON.parse(fs.readFileSync(blueprintPath, "utf8")) as Blueprint;
}

export function findValidator(blueprint: Blueprint, title: string): BlueprintValidator {
  const v = blueprint.validators.find((x) => x.title === title);
  if (!v) {
    throw new Error(`Validator ${title} not found in blueprint`);
  }
  return v;
}

export function applyValidator(
  blueprint: Blueprint,
  title: string,
  params: unknown[],
): Script {
  const validator = findValidator(blueprint, title);
  const scriptCbor =
    params.length === 0
      ? validator.compiledCode
      : applyParamsToScript(validator.compiledCode, params as never);
  return { type: "PlutusV3", script: scriptCbor };
}

export function scriptHash(script: Script): string {
  return validatorToScriptHash(script);
}

export function scriptAddress(
  script: Script,
  network: Network,
): string {
  return validatorToAddress(network, script);
}

/** Resolve credit_script parameter (fixed-point with curator + self hash). */
export function resolveCreditScript(
  blueprint: Blueprint,
  curatorVkh: string,
): Script {
  const title = "credit.credit.mint";
  let creditScriptHash =
    "0000000000000000000000000000000000000000000000000000000000000000";
  let script = applyValidator(blueprint, title, [curatorVkh, creditScriptHash]);
  for (let i = 0; i < 8; i++) {
    const nextHash = scriptHash(script);
    if (nextHash === creditScriptHash) {
      return script;
    }
    creditScriptHash = nextHash;
    script = applyValidator(blueprint, title, [curatorVkh, creditScriptHash]);
  }
  return script;
}
