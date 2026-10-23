use constants.{bps_denominator}
use types.{WaterfallAllocation}

/// Splits **interest only** per phase-1 rules: protocol fee, curator fee, senior, junior.
/// Fees are never taken from `principal_paid` (caller must route principal to vault separately).
pub fn allocate_interest(
  interest_paid: Int,
  protocol_fee_bps: Int,
  curator_fee_bps: Int,
  senior_rate_bps: Int,
) -> WaterfallAllocation {
  if interest_paid <= 0 {
    WaterfallAllocation {
      protocol_fee: 0,
      curator_fee: 0,
      senior_interest: 0,
      junior_interest: 0,
    }
  } else {
    let protocol_fee = interest_paid * protocol_fee_bps / bps_denominator
    let after_protocol = interest_paid - protocol_fee
    let curator_fee = after_protocol * curator_fee_bps / bps_denominator
    let after_curator = after_protocol - curator_fee
    let senior_interest = after_curator * senior_rate_bps / bps_denominator
    let junior_interest = after_curator - senior_interest
    WaterfallAllocation {
      protocol_fee,
      curator_fee,
      senior_interest,
      junior_interest,
    }
  }
}

test allocate_interest_applies_fees_then_senior_then_junior() {
  let alloc =
    allocate_interest(
      interest_paid: 10_000,
      protocol_fee_bps: 200,
      curator_fee_bps: 1_000,
      senior_rate_bps: 8_000,
    )
  expect alloc.protocol_fee == 200
  expect alloc.curator_fee == 980
  expect alloc.senior_interest == 7_056
  expect alloc.junior_interest == 1_764
  alloc.protocol_fee + alloc.curator_fee + alloc.senior_interest + alloc.junior_interest == 10_000
}

test allocate_interest_zero_interest() {
  let alloc =
    allocate_interest(
      interest_paid: 0,
      protocol_fee_bps: 200,
      curator_fee_bps: 1_000,
      senior_rate_bps: 8_000,
    )
  alloc == WaterfallAllocation {
    protocol_fee: 0,
    curator_fee: 0,
    senior_interest: 0,
    junior_interest: 0,
  }
}

test allocate_interest_principal_not_in_function() {
  // Documented invariant: principal bypasses this function entirely.
  let alloc =
    allocate_interest(
      interest_paid: 5_000,
      protocol_fee_bps: 0,
      curator_fee_bps: 0,
      senior_rate_bps: 10_000,
    )
  alloc.junior_interest == 0 && alloc.senior_interest == 5_000
}
