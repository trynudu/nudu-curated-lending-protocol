#!/usr/bin/env python3
"""Sign a RevenueAttestation for credit Repay (stdout JSON with hex fields)."""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from attestation import (
    RevenueAttestationFields,
    sign,
    load_signing_seed,
    digest,
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Sign a nudu RevenueAttestation (NUDU1 layout).")
    parser.add_argument(
        "--input",
        required=True,
        help="Path to JSON attestation (loan_tx_id hex, amounts, valid_until, nonce).",
    )
    parser.add_argument(
        "--seed-file",
        default=os.environ.get("ATTESTER_SIGNING_SEED_FILE", ""),
        help="32-byte raw Ed25519 seed file (or set ATTESTER_SIGNING_SEED_FILE).",
    )
    args = parser.parse_args()
    if not args.seed_file:
        print(
            "error: provide --seed-file or ATTESTER_SIGNING_SEED_FILE",
            file=sys.stderr,
        )
        sys.exit(1)

    payload = json.loads(Path(args.input).read_text())
    fields = RevenueAttestationFields.from_json_dict(payload)
    seed = load_signing_seed(args.seed_file)
    vk, vkh, signature = sign(fields, seed)
    out = {
        "digest": digest(fields).hex(),
        "verification_key": vk.hex(),
        "verification_key_hash": vkh.hex(),
        "signature": signature.hex(),
    }
    json.dump(out, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
