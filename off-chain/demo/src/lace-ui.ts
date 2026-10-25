import { Blockfrost, Lucid, type LucidEvolution, type Network } from "@lucid-evolution/lucid";
import type { Deployment } from "./lib/deployment.js";

const logEl = document.getElementById("log")!;
const walletEl = document.getElementById("wallet")!;
const deploymentEl = document.getElementById("deployment") as HTMLTextAreaElement;

function log(msg: string) {
  logEl.textContent = `${logEl.textContent ?? ""}${msg}\n`;
}

function parseDeployment(): Deployment {
  const raw = deploymentEl.value.trim();
  if (!raw) {
    throw new Error("Paste deployment.json from npm run compile:ids");
  }
  return JSON.parse(raw) as Deployment;
}

async function lucidWithLace(): Promise<LucidEvolution> {
  const apiKey = import.meta.env.VITE_BLOCKFROST_API_KEY as string | undefined;
  if (!apiKey) {
    throw new Error("Set VITE_BLOCKFROST_API_KEY in off-chain/demo/.env");
  }
  const lucid = await Lucid(
    new Blockfrost("https://cardano-preprod.blockfrost.io/api/v0", apiKey),
    "Preprod" as Network,
  );
  const cardano = (window as unknown as { cardano?: Record<string, { enable: () => Promise<unknown> }> })
    .cardano;
  const lace = cardano?.lace ?? cardano?.nufi;
  if (!lace) {
    throw new Error("Lace (or compatible) wallet not found");
  }
  await lucid.selectWallet.fromAPI((await lace.enable()) as never);
  return lucid;
}

document.getElementById("connect")!.addEventListener("click", async () => {
  try {
    const lucid = await lucidWithLace();
    const addr = await lucid.wallet().address();
    walletEl.textContent = addr;
    log(`Connected: ${addr}`);
  } catch (e) {
    log(String(e));
  }
});

document.getElementById("mint-kyc")!.addEventListener("click", () => {
  log(
    "KYC mint requires curator wallet — run: npm run init:vault (CLI) or extend this UI.",
  );
});

document.getElementById("deposit")!.addEventListener("click", () => {
  try {
    parseDeployment();
    log("Senior deposit: run npm run tx:deposit with LP seed file (CLI path).");
  } catch (e) {
    log(String(e));
  }
});
