# Analysis — #62: live-runs and shopping on manifest v2

Issue: https://github.com/mnemcik/cg-extensions/issues/62 · Size proposed: **S** (manifests, docs, versions; one
registry PR) · Step 4 of the cross-repo plan in mnemcik/consigliere#259 (`specs/gh-259-extension-commands/plan.md`).

## Problem (validated)

- `live-runs/cg-extension.json` and `shopping/cg-extension.json` on `main` are `"manifest": 1` with
  `contributes.subcommands` (`live` → `cg-live`, `shop` → `cg-shop`).
- cg 2.0 (consigliere `main`, unreleased; release PR mnemcik/consigliere#312) accepts manifest 1..2, reads commands
  only from `contributes.commands`, rejects `commands` in v1, and ignores `subcommands` like any unknown field
  (#259 spec Q1, Q8; `internal/extension/manifest.go`). After 2.0.0, `cg live` / `cg shop` stop resolving until
  both extensions are on v2.
- cg 1.32.1 refuses any manifest that isn't v1 (`manifest.go:132`, `unsupported manifest schema version`). No
  manifest serves both majors, so this merges only after 2.0.0 is published.

## What the agreed texts already fix

- **#259 spec X2:** `"manifest": 2`; `commands` declares the bare namespace (`live`, `shop`, so `cg shop`,
  `cg shop --help` and `cg live --until-pane x run` reach the binary as today) and each subcommand the binary
  handles (`live run`, `live watch`; `shop add`, `shop list`, …), so permission entries can name them; versions bumped.
- **#259 plan, cross-repo step 4:** PR B as X2, then the registry index bump (versions, "cg 2.0+" in the
  descriptions); prepared early, merged right after the release.
- **#259 spec Q4 / S15:** binaries get the args after the namespace word, and the longest declared command the typed
  words start with runs (`cmd/external.go:113`). So undeclared aliases (`shop ls`, `shop version`, `shop help`,
  `shop -h`) still reach `cg-shop` through the bare `shop` entry with unchanged arguments.
- **#212 (consigliere) decision 9 + Options item 5:** extensions set `requires.cg` only where they depend on a fix;
  a v2 manifest already implies cg ≥ 2.0.0. Neither extension depends on anything after 2.0.0, so no `requires.cg`.
  The owner chose (2026-11-26) to keep "(cg 2.0+)" in the registry descriptions as #259 step 4 says, instead of
  #212 d9's "drop the text", because the 1.33.0 "needs cg 2.0" message (d7) was never released.

## Commands to declare (from the binaries)

- `cg-live` (`live-runs/bin/cg-live`, final `case`): `run`, `watch`; anything else prints usage.
  → `live`, `live run`, `live watch`.
- `cg-shop` (`shopping/bin/cg-shop`, `main`): `add`, `list`|`ls`, `order`, `receive`, `cancel`, `show`,
  `version`|`--version`, `help`|`-h`|`--help`. → `shop`, `shop add`, `shop list`, `shop order`, `shop receive`,
  `shop cancel`, `shop show`. Aliases and help/version stay reachable through `shop`.

## Other places that state the old form or the old minimum

- `live-runs/README.md:22`, `shopping/README.md:22` (contribution table: `subcommands`); `live-runs/README.md:37`
  ("cg 1.30.2 or later"); `shopping/README.md:59` ("cg later than 1.30.1", the co-located subcommand bug);
  `README.md:47` ("manifest (schema v1)").
- Registry `index.json`: descriptions end "(cg 1.30.2+)"; `latestVersion` live-runs 0.1.0 (manifest 0.1.1),
  shopping 0.1.0 (manifest 0.2.0).

## Out of scope

- Step 5 (registry schema drops `subcommands`): its own issue after this merges.
- Registry schema additions for `requires` / `skills` / hook `matcher` / `if`: the #212 / #300 / #301 rollouts.
- `tmux` declares no commands and stays on v1.
