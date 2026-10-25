#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/blueprint/plutus.json"
mkdir -p "$ROOT/blueprint"
RUN_ID="$(gh run list --workflow=continuous-integration.yml --branch=main --limit=1 --json databaseId,conclusion -q '.[] | select(.conclusion=="success") | .databaseId' | head -1)"
if [[ -z "${RUN_ID}" ]]; then
  echo "No successful CI run found." >&2
  exit 1
fi
TMP="$(mktemp -d)"
gh run download "$RUN_ID" -n plutus-blueprint -D "$TMP"
mv "$TMP/plutus.json" "$OUT"
rm -rf "$TMP"
echo "Wrote $OUT from run $RUN_ID"
