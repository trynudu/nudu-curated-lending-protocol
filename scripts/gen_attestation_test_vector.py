#!/usr/bin/env python3
"""Regenerate Ed25519 test signature in lib/test_vectors.ak (attestation v1 layout)."""
from __future__ import annotations

import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VECTORS = ROOT / "lib" / "test_vectors.ak"
SIGNING_SEED = b"\x01" * 32
DOMAIN = b"NUDU1"


def be(value: int, size: int) -> bytes:
    return value.to_bytes(size, byteorder="big", signed=False)


def attestation_signing_bytes() -> bytes:
    tx_id = bytes.fromhex(
        "1111111111111111111111111111111111111111111111111111111111111111"
    )
    return b"".join(
        [
            DOMAIN,
            tx_id,
            be(1, 4),
            be(202_601, 8),
            be(500_000, 8),
            be(500, 8),
            be(10_000, 8),
            be(1_000_000_000_000, 8),
            be(42, 8),
        ]
    )


def main() -> None:
    from nacl.signing import SigningKey

    signing_bytes = attestation_signing_bytes()
    digest = hashlib.blake2b(signing_bytes, digest_size=32).digest()
    sk = SigningKey(SIGNING_SEED)
    vk = bytes(sk.verify_key)
    sig = sk.sign(digest).signature
    vkh = hashlib.blake2b(vk, digest_size=28).digest()

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
    print(f"digest={digest.hex()}")
    print(f"sig={sig.hex()}")
    print(f"vkh={vkh.hex()}")
    print(f"Updated {VECTORS}")


if __name__ == "__main__":
    main()
