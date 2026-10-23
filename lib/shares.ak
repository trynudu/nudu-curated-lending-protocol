/// Shares minted for a deposit (integer division; rounds down — favors the vault).
pub fn shares_for_deposit(
  deposit: Int,
  total_assets: Int,
  total_shares: Int,
) -> Option<Int> {
  if deposit <= 0 {
    None
  } else if total_shares <= 0 {
    Some(deposit)
  } else if total_assets <= 0 {
    None
  } else {
    let minted = deposit * total_shares / total_assets
    if minted <= 0 {
      None
    } else {
      Some(minted)
    }
  }
}

/// USDCx returned when burning `shares_burned` (rounds down — favors the vault).
pub fn assets_for_withdraw(
  shares_burned: Int,
  total_assets: Int,
  total_shares: Int,
) -> Option<Int> {
  if shares_burned <= 0 || total_shares <= 0 || total_assets <= 0 {
    None
  } else if shares_burned > total_shares {
    None
  } else {
    Some(shares_burned * total_assets / total_shares)
  }
}

test shares_for_deposit_first_deposit_is_one_to_one() {
  shares_for_deposit(deposit: 1_000, total_assets: 0, total_shares: 0) == Some(
    1_000,
  )
}

test shares_for_deposit_pro_rata() {
  shares_for_deposit(deposit: 500, total_assets: 2_000, total_shares: 1_000) == Some(
    250,
  )
}

test shares_for_deposit_rejects_zero_deposit() {
  shares_for_deposit(deposit: 0, total_assets: 1_000, total_shares: 100) == None
}

test shares_for_deposit_rejects_dust() {
  shares_for_deposit(deposit: 1, total_assets: 10_000, total_shares: 9_999) == None
}

test assets_for_withdraw_half() {
  assets_for_withdraw(
    shares_burned: 500,
    total_assets: 2_000,
    total_shares: 1_000,
  ) == Some(1_000)
}

test assets_for_withdraw_rejects_over_burn() {
  assets_for_withdraw(
    shares_burned: 1_001,
    total_assets: 2_000,
    total_shares: 1_000,
  ) == None
}

test assets_for_withdraw_rejects_empty_tranche() {
  assets_for_withdraw(shares_burned: 10, total_assets: 0, total_shares: 0) == None
}
