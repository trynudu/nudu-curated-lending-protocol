#!/usr/bin/env python3
"""Cross-check Python attestation encoder against lib/test_vectors.ak constants."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from attestation import (
    TEST_FIXTURE_DIGEST_HEX,
    TEST_FIXTURE_VKH_HEX,
    TEST_SIGNING_SEED,
    digest,
    sign,
    test_fixture_fields,
    _unsigned_be,
)


def test_fixture_digest() -> None:
    d = digest(test_fixture_fields()).hex()
    assert d == TEST_FIXTURE_DIGEST_HEX, f"digest mismatch: {d}"


def test_fixture_vkh() -> None:
    _, vkh, _ = sign(test_fixture_fields(), TEST_SIGNING_SEED)
    assert vkh.hex() == TEST_FIXTURE_VKH_HEX, f"vkh mismatch: {vkh.hex()}"


def test_rejects_oversized_int() -> None:
    try:
        _unsigned_be(2**64, 8, "period_id")
    except ValueError:
        return
    raise AssertionError("expected ValueError for oversized int")


def main() -> None:
    test_fixture_digest()
    test_fixture_vkh()
    test_rejects_oversized_int()
    print("ok: attestation encoder matches on-chain test vectors")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"fail: {exc}", file=sys.stderr)
        sys.exit(1)
