# Spec — #62: live-runs and shopping on manifest v2

Size **S** (plan: none). Implements mnemcik/consigliere#259 spec X2 and plan cross-repo step 4. Analysis:
[analysis.md](analysis.md).

## Changes

- **M1** `live-runs/cg-extension.json`: `"manifest": 2`; `contributes.subcommands` removed; `contributes.commands`
  = `live`, `live run`, `live watch`, each with `"binary": "cg-live"`. `version` 0.1.1 → **0.2.0**.
- **M2** `shopping/cg-extension.json`: `"manifest": 2`; `contributes.subcommands` removed; `contributes.commands`
  = `shop`, `shop add`, `shop list`, `shop order`, `shop receive`, `shop cancel`, `shop show`, each with
  `"binary": "cg-shop"`. `version` 0.2.0 → **0.3.0**.
- **M3** No `requires` field in either manifest; no other contribution changes. The only binary change:
  `shopping/bin/cg-shop` `VERSION` 0.2.0 → 0.3.0, so `cg shop version` matches the manifest (`cg-live` has no version
  string).
- **M4** Deliberately not declared: `cg-shop`'s aliases and meta words (`ls`, `version` / `--version`, `help` / `-h` /
  `--help`). cg runs the longest declared command the typed words start with, and command words end at the first
  flag (#259 S15, Q7), so they reach `cg-shop` through `shop` with unchanged arguments; declaring only the canonical
  subcommands keeps permission entries to one name per action.
- **D1** Docs: each extension's README contribution table names `commands` (with the declared commands); the
  minimum-version lines become "cg 2.0 or later" (`live-runs/README.md`, `shopping/README.md`, replacing the
  1.30.x bug note); `live-runs/notes/live-runs.md` drops "With cg 1.x, or" from its last sentence (0.2.0 can't be
  installed on cg 1.x; the shopping note stays unchanged); `README.md` layout comment no longer says "schema v1" only; each CHANGELOG gets the new version
  with **Changed (breaking): requires cg 2.0** and how to update: update cg on every machine that shares the
  workspace first (`cg update upgrade`, or `brew upgrade --cask cg` for a Homebrew install), then
  `cg extension update`, then commit.
- **R1** Registry (mnemcik/cg-extensions-registry, its own PR, `Fixes mnemcik/cg-extensions#62`): `index.json`
  `live-runs` and `shopping` entries: `latestVersion` = the new manifest versions; descriptions end
  "(cg 2.0+)" instead of "(cg 1.30.2+)". Nothing else in the index.
- **R2** Both PRs say `Fixes` for #62, as each repo's rules require; the cg-extensions PR merges first and closes
  it, the registry PR merges minutes later (Merge order). Accepted: #62 shows closed for that gap.

## Acceptance criteria

- **A1** Both manifests validate against the registry schema on `main` (the `validate.yml` job passes).
- **A2** On cg 2.0 built from consigliere `main` (during development) **and** on the released v2.0.0 binary
  (before merge), in a scratch workspace with both extensions installed from this branch
  (`cg extension install https://github.com/mnemcik/cg-extensions --path <ext> --ref gh-62-manifest-v2`):
  - `cg shop`, `cg shop --help`, `cg shop ls`, `cg shop add <title> …`, `cg shop list` behave as with 0.2.0 on
    cg 1.32.1; `cg shop version` prints `cg-shop 0.3.0`;
  - `cg live` and `cg live --until-pane x run` print `cg-live`'s usage and exit 2, as on cg 1.32.1;
    `cg live run …` and `cg live watch --once` behave as on cg 1.32.1;
  - `cg extension list` shows the declared commands for both.
- **A3** Each extension's own test suite (`<ext>/tests/run.sh`) passes unchanged.
- **A4** On cg 1.32.1, installing either extension from this branch fails with
  `unsupported manifest schema version 2` (expected; recorded, not fixed). Run before any cg 2.0 build (the
  `main` build for A2 included) replaces 1.32.1 on `PATH` on this machine (one machine).
- **A5** No `subcommands` key remains in either manifest; `grep -rn subcommands live-runs shopping` finds only
  CHANGELOG history.

## Merge order

The PR and the registry PR are opened and reviewed before mnemcik/consigliere#312 merges. They merge only after
2.0.0 is published with its release assets and A2 has passed on the released binary: this PR first, the registry PR
right after.

The PR is opened when M1–M4, D1, A1, A3, A4 and the cg-`main` half of A2 are done. The released-binary half of A2
can only run after the release: the PR description lists it as pending, and its result is posted on the PR before
the maintainer's merge. Any update from `main` at that point needs a new `impact-review` on the new head.
