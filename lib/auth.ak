use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}

pub fn signed_by(
  extra: List<VerificationKeyHash>,
  who: VerificationKeyHash,
) -> Bool {
  list.has(extra, who)
}
