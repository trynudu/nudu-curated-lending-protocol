import type { Assets, OutputDatum } from "@lucid-evolution/lucid";
import type { LucidEvolution } from "@lucid-evolution/lucid";

type TxBuilder = ReturnType<LucidEvolution["newTx"]>;

export function payWithInlineDatum(
  tx: TxBuilder,
  address: string,
  assets: Assets,
  datumCbor: string,
): TxBuilder {
  return tx.pay.ToAddressWithData(address, { kind: "inline", value: datumCbor }, assets);
}

export function payAssets(
  tx: TxBuilder,
  address: string,
  assets: Assets,
  datum?: OutputDatum,
): TxBuilder {
  if (datum) {
    return tx.pay.ToAddressWithData(address, datum, assets);
  }
  return tx.pay.ToAddress(address, assets);
}
