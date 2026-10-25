use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use cardano/address.{VerificationKey}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{Output}
use constants.{usdcx_asset_name}
use types.{VaultConfig, VaultDatum, WaterfallAllocation}
use waterfall.{allocate_interest}

/// Net USDCx increase on the vault UTxO after fees leave to treasury and curator.
pub fn vault_repay_usdcx_delta(
  principal_paid: Int,
  interest_paid: Int,
  alloc: WaterfallAllocation,
) -> Int {
  principal_paid + interest_paid - alloc.protocol_fee - alloc.curator_fee
}

pub fn apply_repay(
  datum: VaultDatum,
  principal_paid: Int,
  interest_paid: Int,
) -> Option<(VaultDatum, WaterfallAllocation)> {
  if principal_paid <= 0 && interest_paid <= 0 {
    None
  } else if principal_paid > datum.deployed_outstanding {
    None
  } else {
    let alloc = allocate_interest(
      interest_paid,
      datum.config.protocol_fee_bps,
      datum.config.curator_fee_bps,
      datum.config.senior_rate_bps,
    )
    Some(
      (
        VaultDatum {
          ..datum,
          deployed_outstanding: datum.deployed_outstanding - principal_paid,
          senior_assets: datum.senior_assets + alloc.senior_interest,
          junior_assets: datum.junior_assets + alloc.junior_interest,
        },
        alloc,
      ),
    )
  }
}

fn usdcx_to_vkh(
  outputs: List<Output>,
  usdcx_policy: PolicyId,
  recipient: VerificationKeyHash,
  min_amount: Int,
) -> Bool {
  if min_amount <= 0 {
    True
  } else {
    list.any(
      outputs,
      fn(out) {
        when out.address.payment_credential is {
          VerificationKey(vkh) ->
            if vkh == recipient {
              quantity_of(out.value, usdcx_policy, usdcx_asset_name()) >= min_amount
            } else {
              False
            }
          _ -> False
        }
      },
    )
  }
}

pub fn fee_outputs_valid(
  outputs: List<Output>,
  usdcx_policy: PolicyId,
  curator: VerificationKeyHash,
  config: VaultConfig,
  alloc: WaterfallAllocation,
) -> Bool {
  and {
    usdcx_to_vkh(
      outputs,
      usdcx_policy,
      config.protocol_treasury,
      alloc.protocol_fee,
    ),
    usdcx_to_vkh(outputs, usdcx_policy, curator, alloc.curator_fee),
  }
}

pub fn validate_vault_repay(
  input_datum: VaultDatum,
  output_datum: VaultDatum,
  principal_paid: Int,
  interest_paid: Int,
  input_usdcx: Int,
  output_usdcx: Int,
  outputs: List<Output>,
) -> Bool {
  when apply_repay(input_datum, principal_paid, interest_paid) is {
    None -> False
    Some((expected, alloc)) -> {
      let delta = vault_repay_usdcx_delta(principal_paid, interest_paid, alloc)
      and {
        output_datum == expected,
        input_datum.senior_shares == output_datum.senior_shares,
        input_datum.junior_shares == output_datum.junior_shares,
        output_usdcx - input_usdcx == delta,
        fee_outputs_valid(
          outputs,
          input_datum.usdcx_policy,
          input_datum.curator,
          input_datum.config,
          alloc,
        ),
      }
    }
  }
}

test apply_repay_updates_tranches_and_deployed() {
  let config = VaultConfig {
    max_single_borrower_bps: 1_000,
    protocol_fee_bps: 200,
    curator_fee_bps: 1_000,
    senior_rate_bps: 8_000,
    attester: #"11",
    protocol_treasury: #"22",
  }
  let datum = VaultDatum {
    curator: #"aa",
    usdcx_policy: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    whitelist_policy: #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    share_policy: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    credit_script: #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    config,
    senior_shares: 100,
    junior_shares: 50,
    senior_assets: 1_000,
    junior_assets: 500,
    deployed_outstanding: 5_000,
  }
  when apply_repay(datum, 1_000, 10_000) is {
    None -> False
    Some((next, alloc)) -> and {
        next.deployed_outstanding == 4_000,
        next.senior_assets == datum.senior_assets + alloc.senior_interest,
        next.junior_assets == datum.junior_assets + alloc.junior_interest,
        vault_repay_usdcx_delta(1_000, 10_000, alloc) == 1_000 + 10_000 - alloc.protocol_fee - alloc.curator_fee,
      }
  }
}
