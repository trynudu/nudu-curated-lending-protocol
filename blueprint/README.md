# Plutus blueprint

`plutus.json` is produced by `aiken build -o blueprint/plutus.json` (see CI). Commit a fetched copy for offline `compile:ids`, or run `./scripts/fetch-plutus-blueprint.sh` after a green build.

Fetch the latest from GitHub Actions:

```bash
./scripts/fetch-plutus-blueprint.sh
```

Or build locally if your `aiken` binary supports it:

```bash
aiken build -o blueprint/plutus.json
```
