"""Off-chain encoder for on-chain RevenueAttestation (must match lib/attestation.ak)."""
from __future__ import annotations

import hashlib
from dataclasses import dataclass

DOMAIN = b"NUDU1"
LOAN_TX_ID_LEN = 32
SIGNING_SEED_LEN = 32

# Digest from test fixture; must match lib/test_vectors.ak attestation_digest_matches_off_chain_reference.
TEST_FIXTURE_DIGEST_HEX = (
    "923c21d0b4308fbea3be72fc3dc5a53d474f8e34af11d5d1d7b0b457425149de"
)
TEST_FIXTURE_VKH_HEX = "0d6a577e9441ad8ed9663931906e4d43ece8f82c712b1d0235affb06"
TEST_SIGNING_SEED = b"\x01" * 32


@dataclass(frozen=True)
class RevenueAttestationFields:
    loan_tx_id: bytes
    loan_output_index: int
    period_id: int
    attested_revenue: int
    principal_paid: int
    interest_paid: int
    valid_until: int
    nonce: int

    @classmethod
    def from_json_dict(cls, data: dict) -> RevenueAttestationFields:
        tx_hex = data["loan_tx_id"]
        if isinstance(tx_hex, str):
            if tx_hex.startswith("0x"):
                tx_hex = tx_hex[2:]
            loan_tx_id = bytes.fromhex(tx_hex)
        else:
            raise ValueError("loan_tx_id must be a hex string")
        return cls(
            loan_tx_id=loan_tx_id,
            loan_output_index=int(data["loan_output_index"]),
            period_id=int(data["period_id"]),
            attested_revenue=int(data["attested_revenue"]),
            principal_paid=int(data["principal_paid"]),
            interest_paid=int(data["interest_paid"]),
            valid_until=int(data["valid_until"]),
            nonce=int(data["nonce"]),
        )


def _unsigned_be(value: int, size: int, field: str) -> bytes:
    if value < 0:
        raise ValueError(f"{field} must be non-negative, got {value}")
    try:
        return value.to_bytes(size, byteorder="big", signed=False)
    except OverflowError as exc:
        raise ValueError(f"{field} does not fit in {size} bytes") from exc


def _validate_fields(fields: RevenueAttestationFields) -> None:
    if len(fields.loan_tx_id) != LOAN_TX_ID_LEN:
        raise ValueError(
            f"loan_tx_id must be {LOAN_TX_ID_LEN} bytes, got {len(fields.loan_tx_id)}"
        )
    _unsigned_be(fields.loan_output_index, 4, "loan_output_index")
    for name in (
        "period_id",
        "attested_revenue",
        "principal_paid",
        "interest_paid",
        "valid_until",
        "nonce",
    ):
        _unsigned_be(getattr(fields, name), 8, name)


def signing_bytes(fields: RevenueAttestationFields) -> bytes:
    _validate_fields(fields)
    ref_part = fields.loan_tx_id + _unsigned_be(
        fields.loan_output_index, 4, "loan_output_index"
    )
    ints = _unsigned_be(fields.period_id, 8, "period_id") + _unsigned_be(
        fields.attested_revenue, 8, "attested_revenue"
    )
    ints2 = _unsigned_be(fields.principal_paid, 8, "principal_paid") + _unsigned_be(
        fields.interest_paid, 8, "interest_paid"
    )
    ints3 = _unsigned_be(fields.valid_until, 8, "valid_until") + _unsigned_be(
        fields.nonce, 8, "nonce"
    )
    return DOMAIN + ref_part + ints + ints2 + ints3


def digest(fields: RevenueAttestationFields) -> bytes:
    return hashlib.blake2b(signing_bytes(fields), digest_size=32).digest()


def verification_key_hash(verification_key: bytes) -> bytes:
    return hashlib.blake2b(verification_key, digest_size=28).digest()


def sign(
    fields: RevenueAttestationFields, seed: bytes
) -> tuple[bytes, bytes, bytes]:
    if len(seed) != SIGNING_SEED_LEN:
        raise ValueError(f"signing seed must be {SIGNING_SEED_LEN} bytes")
    from nacl.signing import SigningKey

    msg = digest(fields)
    sk = SigningKey(seed)
    vk = bytes(sk.verify_key)
    signature = sk.sign(msg).signature
    vkh = verification_key_hash(vk)
    return vk, vkh, signature


def test_fixture_fields() -> RevenueAttestationFields:
    return RevenueAttestationFields(
        loan_tx_id=bytes.fromhex(
            "1111111111111111111111111111111111111111111111111111111111111111"
        ),
        loan_output_index=1,
        period_id=202_601,
        attested_revenue=500_000,
        principal_paid=500,
        interest_paid=10_000,
        valid_until=1_000_000_000_000,
        nonce=42,
    )


def load_signing_seed(path: str) -> bytes:
    raw = open(path, "rb").read()
    if len(raw) != SIGNING_SEED_LEN:
        raise ValueError(
            f"seed file must be exactly {SIGNING_SEED_LEN} bytes, got {len(raw)}"
        )
    return raw
