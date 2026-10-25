#!/usr/bin/env python3
"""Regenerate Ed25519 test signature in lib/test_vectors.ak (attestation v1 layout)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from attestation import TEST_SIGNING_SEED, digest, sign, test_fixture_fields

ROOT = Path(__file__).resolve().parents[1]
VECTORS = ROOT / "lib" / "test_vectors.ak"


def main() -> None:
    fields = test_fixture_fields()
    signing_digest = digest(fields)
    _, vkh, sig = sign(fields, TEST_SIGNING_SEED)

    text = VECTORS.read_text()
    text = re.sub(
        r'pub fn test_attester_vkey_hash\(\) -> VerificationKeyHash \{\s*\n\s*#"[^"]+"\s*\n\}',
        f'pub fn test_attester_vkey_hash() -> VerificationKeyHash {{\n  #"{vkh.hex()}"\n}}',
        text,
        count=1,
    )
    text = re.sub(
        r'pub fn test_attester_signature\(\) -> Signature \{\s*\n\s*#"[^"]+"\s*\n\}',
        f'pub fn test_attester_signature() -> Signature {{\n  #"{sig.hex()}"\n}}',
        text,
        count=1,
    )
    VECTORS.write_text(text)
    print(f"digest={signing_digest.hex()}")
    print(f"sig={sig.hex()}")
    print(f"vkh={vkh.hex()}")
    print(f"Updated {VECTORS}")


if __name__ == "__main__":
    main()
