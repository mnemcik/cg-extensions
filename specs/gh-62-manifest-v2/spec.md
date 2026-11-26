# Spec — #62: live-runs and shopping on manifest v2

Size **S** (plan: none). Implements mnemcik/consigliere#259 spec X2 and plan cross-repo step 4. Analysis:
[analysis.md](analysis.md).

## Changes

- **M1** `live-runs/cg-extension.json`: `"manifest": 2`; `contributes.subcommands` removed; `contributes.commands`
  = `live`, `live run`, `live watch`, each with `"binary": "cg-live"`. `version` 0.1.1 → **0.2.0**.
- **M2** `shopping/cg-extension.json`: `"manifest": 2`; `contributes.subcommands` removed; `contributes.commands`
  = `shop`, `shop add`, `shop list`, `shop order`, `shop receive`, `shop cancel`, `shop show`, each with
  `"binary": "cg-shop"`. `version` 0.2.0 → **0.3.0**.
- **M3** No `requires` field in either manifest; no other contribution changes; no binary changes.
- **D1** Docs: each extension's README contribution table names `commands` (with the declared commands); the
  minimum-version lines become "cg 2.0 or later" (`live-runs/README.md`, `shopping/README.md`, replacing the
  1.30.x bug note); `README.md` layout comment no longer says "schema v1" only; each CHANGELOG gets the new version
  with **Changed (breaking): requires cg 2.0** and how to update (`cg update upgrade`, then
  `cg extension update`).
- **R1** Registry (mnemcik/cg-extensions-registry, its own PR, `Fixes mnemcik/cg-extensions#62`): `index.json`
  `live-runs` and `shopping` entries: `latestVersion` = the new manifest versions; descriptions end
  "(cg 2.0+)" instead of "(cg 1.30.2+)". Nothing else in the index.

## Acceptance criteria

- **A1** Both manifests validate against the registry schema on `main` (the `validate.yml` job passes).
- **A2** On cg 2.0 built from consigliere `main` (during development) **and** on the released v2.0.0 binary
  (before merge), in a scratch workspace with both extensions installed from this branch
  (`cg extension install https://github.com/mnemcik/cg-extensions --path <ext> --ref gh-62-manifest-v2`):
  - `cg shop`, `cg shop --help`, `cg shop ls`, `cg shop add <title> …`, `cg shop list`, `cg shop version` behave as
    with 0.2.0 on cg 1.32.1;
  - `cg live` (usage), `cg live run …`, `cg live watch --once`, `cg live --until-pane x run` reach `cg-live`
    with the same arguments as before;
  - `cg extension list` shows the declared commands for both.
- **A3** Each extension's own test suite (`<ext>/tests/run.sh`) passes unchanged.
- **A4** On cg 1.32.1, installing either extension from this branch fails with
  `unsupported manifest schema version 2` (expected; recorded, not fixed).
- **A5** No `subcommands` key remains in either manifest; `grep -rn subcommands live-runs shopping` finds only
  CHANGELOG history.

## Merge order

The PR and the registry PR are opened and reviewed before mnemcik/consigliere#312 merges. They merge only after
2.0.0 is published with its release assets and A2 has passed on the released binary: this PR first, the registry PR
right after.
