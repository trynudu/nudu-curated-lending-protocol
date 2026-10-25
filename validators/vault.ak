use cardano/address.{Script}
use cardano/assets.{quantity_of}
use cardano/transaction.{
  InlineDatum, OutputReference, Transaction, find_script_outputs, resolve_input,
}
use constants.{usdcx_asset_name}
use types.{VaultDatum, VaultRedeemer}
use vault_logic.{
  share_deltas_for_redeemer, validate_share_mint, validate_vault_spend,
}

/// Tranched vault — deposit, withdraw, and curator config updates.
validator vault {
  spend(
    datum: Option<VaultDatum>,
    redeemer: VaultRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(input_datum) = datum
    let own_input = resolve_input(self.inputs, own_ref)
    expect Script(vault_hash) = own_input.address.payment_credential
    expect [continuing] = find_script_outputs(self.outputs, vault_hash)
    expect InlineDatum(output_raw) = continuing.datum
    expect output_datum: VaultDatum = output_raw
    let input_usdcx = quantity_of(
      own_input.value,
      input_datum.usdcx_policy,
      usdcx_asset_name(),
    )
    let output_usdcx = quantity_of(
      continuing.value,
      input_datum.usdcx_policy,
      usdcx_asset_name(),
    )
    expect Some((senior_delta, junior_delta)) = share_deltas_for_redeemer(
      input_datum,
      output_datum,
      redeemer,
      input_usdcx,
      output_usdcx,
    )
    and {
      validate_vault_spend(
        input_datum,
        output_datum,
        redeemer,
        input_usdcx,
        output_usdcx,
        self.extra_signatories,
        self.inputs,
        self.reference_inputs,
        self.outputs,
      ),
      validate_share_mint(
        self.mint,
        input_datum.share_policy,
        senior_delta,
        junior_delta,
      ),
    }
  }

  else(_) {
    fail
  }
}
