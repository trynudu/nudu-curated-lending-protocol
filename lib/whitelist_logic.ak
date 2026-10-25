use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use auth.{signed_by}
use cardano/address.{VerificationKey, from_verification_key}
use cardano/assets.{Assets, PolicyId, from_asset, quantity_of}
use cardano/transaction.{Input, NoDatum, Output, Transaction}
use constants.{whitelist_asset_name}

pub fn mint_delta_for_kyc() -> Int {
  1
}

pub fn burn_delta_for_kyc() -> Int {
  -1
}

/// Only the whitelist asset may change under this policy, by exactly ±1.
pub fn validate_policy_mint_delta(
  mint: Assets,
  policy_id: PolicyId,
  expected_delta: Int,
) -> Bool {
  quantity_of(mint, policy_id, whitelist_asset_name()) == expected_delta
}

/// Holder receives the minted KYC token on an output (or holds input when burning).
pub fn output_pays_to_holder(
  outputs: List<Output>,
  holder: VerificationKeyHash,
  policy_id: PolicyId,
  min_qty: Int,
) -> Bool {
  list.any(
    outputs,
    fn(out) {
      when out.address.payment_credential is {
        VerificationKey(vkh) ->
          if vkh == holder {
            quantity_of(out.value, policy_id, whitelist_asset_name()) >= min_qty
          } else {
            False
          }
        _ -> False
      }
    },
  )
}

pub fn input_holds_kyc(
  inputs: List<Input>,
  holder: VerificationKeyHash,
  policy_id: PolicyId,
) -> Bool {
  list.any(
    inputs,
    fn(input) {
      when input.output.address.payment_credential is {
        VerificationKey(vkh) ->
          if vkh == holder {
            quantity_of(input.output.value, policy_id, whitelist_asset_name()) >= 1
          } else {
            False
          }
        _ -> False
      }
    },
  )
}

pub fn validate_mint_kyc(
  self: Transaction,
  policy_id: PolicyId,
  curator: VerificationKeyHash,
  holder: VerificationKeyHash,
) -> Bool {
  and {
    signed_by(self.extra_signatories, curator),
    validate_policy_mint_delta(self.mint, policy_id, mint_delta_for_kyc()),
    output_pays_to_holder(self.outputs, holder, policy_id, mint_delta_for_kyc()),
  }
}

pub fn validate_burn_kyc(
  self: Transaction,
  policy_id: PolicyId,
  curator: VerificationKeyHash,
  holder: VerificationKeyHash,
) -> Bool {
  and {
    signed_by(self.extra_signatories, curator),
    validate_policy_mint_delta(self.mint, policy_id, burn_delta_for_kyc()),
    input_holds_kyc(self.inputs, holder, policy_id),
  }
}

test validate_mint_kyc_requires_curator_signature() {
  let policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let curator = #"aa"
  let holder = #"cc"
  let tx = Transaction {
    ..cardano / transaction.placeholder,
    extra_signatories: [curator],
    mint: from_asset(policy, whitelist_asset_name(), mint_delta_for_kyc()),
    outputs: [
      Output {
        address: from_verification_key(holder),
        value: from_asset(policy, whitelist_asset_name(), mint_delta_for_kyc()),
        datum: NoDatum,
        reference_script: None,
      },
    ],
  }
  validate_mint_kyc(tx, policy, curator, holder)
}

test validate_mint_kyc_fails_without_curator() {
  let policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  !validate_mint_kyc(cardano / transaction.placeholder, policy, #"aa", #"cc")
}

test validate_policy_mint_rejects_wrong_quantity() {
  let policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  !validate_policy_mint_delta(
    from_asset(policy, whitelist_asset_name(), 2),
    policy,
    mint_delta_for_kyc(),
  )
}

test validate_burn_kyc_fails_without_input_token() {
  let policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let curator = #"aa"
  let holder = #"cc"
  let tx = Transaction {
    ..cardano / transaction.placeholder,
    extra_signatories: [curator],
    mint: from_asset(policy, whitelist_asset_name(), burn_delta_for_kyc()),
  }
  !validate_burn_kyc(tx, policy, curator, holder)
}
