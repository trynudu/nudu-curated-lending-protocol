#!/usr/bin/env python3
"""Print attester Ed25519 vkey and blake2b-224 vkh from a 32-byte raw seed file."""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from attestation import load_signing_seed, verification_key_hash


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: attester_credentials.py <32-byte-seed-file>", file=sys.stderr)
        sys.exit(1)
    seed = load_signing_seed(sys.argv[1])
    from nacl.signing import SigningKey

    vk = bytes(SigningKey(seed).verify_key)
    print(
        json.dumps(
            {
                "verification_key": vk.hex(),
                "verification_key_hash": verification_key_hash(vk).hex(),
            }
        )
    )


if __name__ == "__main__":
    main()
