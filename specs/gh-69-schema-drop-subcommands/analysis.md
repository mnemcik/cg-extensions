# Analysis — #69: registry schema still accepts `subcommands`

Issue: https://github.com/mnemcik/cg-extensions/issues/69 · Size proposed: **S** (one schema block; plan: none) ·
Step 5 of the cross-repo plan in mnemcik/consigliere#259 (`specs/gh-259-extension-commands/plan.md`, "Cross-repo").

## Problem (validated on `main`, 2026-11-27)

- mnemcik/cg-extensions-registry `schema/cg-extension.schema.json` (`ff87e6e`) still defines
  `contributes.subcommands` (`namespace` + `binary`), allowed in `"manifest": 1` and `"manifest": 2` alike.
- cg 2.0.0 (consigliere `main`, `internal/extension/manifest.go`) has no `subcommands` field: the manifest is read
  with plain `json.Unmarshal`, so the key is dropped like any unknown field, and commands come only from
  `contributes.commands` in a v2 manifest. consigliere `docs/extensions.md:135`, `EXTENSIONS.md:89` and the 2.0.0
  CHANGELOG already say `subcommands` is no longer read.
- So a manifest whose commands are declared only in `subcommands` passes the schema (and the cg-extensions
  `validate.yml` job, which validates every `*/cg-extension.json` against the schema on registry `main`), installs on
  cg 2.0, and has no commands, with no error.
- No manifest uses it: on cg-extensions `main` (`b9710d0`) no `*/cg-extension.json` contains `subcommands`
  (9 manifests are v1, 2 are v2). All 11 registry index entries point at cg-extensions; there is no third-party entry.
  No open PR in either repo touches a manifest or the schema.
- What reads the schema: the cg-extensions `validate.yml` job and authors' editors/validators via `$schema`. cg
  itself (1.x and 2.0) never reads it; it validates manifests in Go. So the schema change changes no cg behaviour; it
  changes what CI and authors' tooling accept.

## Already agreed

- #259 spec **X1**: "the manifest schema accepts `manifest: 2` and `commands`; `subcommands` is removed once no
  indexed manifest uses it." That condition now holds (#64 merged 2026-11-27).
- #259 plan, cross-repo step 5: "Registry: remove `subcommands` from the schema (X1, second half)."

## Recommendation

Remove `contributes.subcommands` from the schema, in both manifest versions. A manifest carrying it then fails with
the schema's existing `additionalProperties: false` error on `contributes`, which names the key. `"manifest": 1`
stays valid without it (cg 2.0 still reads v1 manifests; 9 indexed extensions are v1).

## Alternative considered

**Keep `subcommands` valid in `"manifest": 1` only** (an `allOf` rule: `subcommands` present → `manifest` const 1).
For: a manifest written for cg 1.x only (which reads `subcommands` in v1) would still validate. Against: that is
exactly the manifest that installs on cg 2.0 with no commands and no error, the problem this issue is about; it
contradicts the agreed X1 ("removed"); and no indexed manifest needs it. Not recommended.

## Effects

- First-party: none; every manifest on `main` validates against the changed schema (checked in the spec's A2).
- Third-party (none indexed today): an author still on `subcommands` gets a validation error from their own tooling
  once they validate against registry `main` (the `$id` is unversioned, so there is no older schema to pin). Their
  manifest keeps working on cg 1.x and keeps contributing no commands on cg 2.0, as today; the fix is the documented
  migration (`commands` and `"manifest": 2`, consigliere `EXTENSIONS.md`).
- cg 1.x users: unaffected (cg doesn't read the schema).
- Reversible: one block in one file; reverting the commit restores it. No cg release is involved, and cg-extensions CI
  picks up either state on its next run (it fetches the schema from registry `main`).
