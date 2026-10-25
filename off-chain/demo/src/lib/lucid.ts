import {
  Blockfrost,
  Lucid,
  type LucidEvolution,
  type Network,
  type UTxO,
} from "@lucid-evolution/lucid";
import fs from "node:fs";
import "dotenv/config";

export type NetworkName = "Preprod" | "Mainnet";

export function networkFromEnv(): NetworkName {
  const n = process.env.CARDANO_NETWORK ?? "Preprod";
  if (n === "Mainnet" || n === "Preprod") {
    return n;
  }
  throw new Error("CARDANO_NETWORK must be Preprod or Mainnet");
}

export async function lucidFromSeed(seed: string): Promise<LucidEvolution> {
  const network = networkFromEnv();
  const apiKey = process.env.BLOCKFROST_API_KEY;
  if (!apiKey) {
    throw new Error("Set BLOCKFROST_API_KEY in .env (preprod project id).");
  }
  const lucid = await Lucid(
    new Blockfrost(
      `https://cardano-${network.toLowerCase()}.blockfrost.io/api/v0`,
      apiKey,
    ),
    network as Network,
  );
  lucid.selectWallet.fromSeed(seed);
  return lucid;
}

export function loadSeedFromFile(path: string): string {
  const raw = fs.readFileSync(path, "utf8").trim();
  if (raw.includes(" ")) {
    return raw;
  }
  const hex = fs.readFileSync(path);
  if (hex.length === 32) {
    throw new Error(
      "Use a BIP39 seed phrase file for Lucid, not a raw 32-byte file. Attester raw seed is only for scripts/sign_attestation.py.",
    );
  }
  return raw;
}

export async function lucidFromEnvRole(
  role: "CURATOR" | "LP" | "BORROWER",
): Promise<LucidEvolution> {
  const file = process.env[`${role}_SEED_FILE`];
  if (!file) {
    throw new Error(`Set ${role}_SEED_FILE in .env to a BIP39 seed phrase file.`);
  }
  return lucidFromSeed(loadSeedFromFile(file));
}

export function lovelaceOf(utxo: UTxO): bigint {
  return utxo.assets.lovelace ?? 0n;
}
