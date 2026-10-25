# Preprod demo (Lace + CLI)

Pilot flow on **Cardano preprod** using [`off-chain/demo/`](../off-chain/demo). Lace signs transaction bodies; the revenue attester uses [`scripts/sign_attestation.py`](../scripts/sign_attestation.py) (not Lace `signData`).

## Prerequisites

1. Three **Lace** wallets on **Preprod** (curator, senior LP, borrower) funded with tADA from a [preprod faucet](https://docs.cardano.org/cardano-testnets/tools/faucet).
2. **Blockfrost** preprod project id in `.env`.
3. **Blueprint:** `blueprint/plutus.json` from CI (`./scripts/fetch-plutus-blueprint.sh`) or local `aiken build -I -o blueprint/plutus.json`.
4. **Attester:** 32-byte raw seed file (same layout as tests); `verification_key_hash` must match `VaultConfig.attester` in the vault datum.
5. **Curator / LP / borrower:** BIP39 seed phrase files (24 words) for Lucid CLI — export from Lace or use dedicated demo seeds (never mainnet, never commit).

## Environment

Copy repo [`.env.example`](../.env.example) to `.env` and `off-chain/demo/.env`:

```bash
BLOCKFROST_API_KEY=preprod...
CARDANO_NETWORK=Preprod
ATTESTER_SIGNING_SEED_FILE=/secure/attester.seed
CURATOR_SEED_FILE=/secure/curator.mnemonic
LP_SEED_FILE=/secure/lp.mnemonic
BORROWER_SEED_FILE=/secure/borrower.mnemonic
VITE_BLOCKFROST_API_KEY=preprod...   # for npm run dev (Lace UI)
```

## Order of operations

From `off-chain/demo/`:

```bash
npm install
pip install -r ../../scripts/requirements.txt

# 1) Script IDs and addresses
npm run mint:pilot-usdcx    # curator mints demo USDCx (native policy)
npm run fund:demo-wallets   # curator sends USDCx to LP + borrower
npm run compile:ids         # writes deployment.json

# 2) On-chain bootstrap
npm run init:vault          # KYC token to LP + vault UTxO with datum

# 3) Demo lending flow
npm run tx:deposit          # senior LP deposits pilot USDCx
npm run tx:disburse         # curator opens loan + pays borrower
# After disburse, note loan tx id + output index from explorer
export LOAN_TX_ID=...
export LOAN_OUTPUT_INDEX=0
npm run tx:repay            # borrower-signed repay (vault + credit + fees + Python attestation)

# Optional Lace UI
npm run dev                 # connect Lace, paste deployment.json
```

## Role matrix

| Step | Who signs (Lace / CLI seed) | Notes |
| --- | --- | --- |
| Pilot USDCx mint | Curator | Native “sig” mint policy |
| `compile:ids` | — | Reads wallet vkh + attester seed |
| Init vault + KYC | Curator | Whitelist mint + vault output |
| Senior deposit | LP | KYC in wallet; vault + share mint |
| Disburse | Curator | Vault spend + credit mint |
| Repay | Borrower (+ attestation CLI) | Co-spend vault; Ed25519 attestation in redeemer |

## Troubleshooting

- **Invalid attestation:** Run `python3 ../../scripts/test_attestation.py` and `aiken check -D`. Loan ref in JSON must match the spent loan UTxO.
- **Missing blueprint:** Run `./scripts/fetch-plutus-blueprint.sh` after a green CI build on `main`.
- **Deposit fails:** Output vault datum must reflect share math; first senior deposit is 1:1 in the demo builder.

## Out of scope

Mainnet USDCx and production indexer.
