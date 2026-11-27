# Spec — #69: registry schema drops `subcommands`

Size **S** (plan: none). Implements mnemcik/consigliere#259 spec X1 (second half) and plan cross-repo step 5.
Analysis: [analysis.md](analysis.md).

## Changes

- **S1** mnemcik/cg-extensions-registry `schema/cg-extension.schema.json`: the `contributes.subcommands` property is
  removed. `contributes` keeps `additionalProperties: false`, so a manifest with `subcommands` (v1 or v2) is
  invalid.
- **S2** Same file: the `contributes.commands` description ends with "Replaces v1's subcommands, which cg 2.0 doesn't
  read." (Q3). Nothing else in the schema changes: `manifest` stays `enum [1, 2]`, and the `allOf` rules and every
  other property are untouched.
- **S3** No other file changes in the registry (`index.json`, `index.schema.json`, `README.md` unchanged; the README
  already describes the schema as "v1, and v2 from cg 2.0").
- **S4** Two PRs (Q4): the registry PR with S1–S2, `Fixes mnemcik/cg-extensions#69`; and a cg-extensions PR with
  only this `specs/gh-69-schema-drop-subcommands/` folder, `Refs #69`. Either can merge first; neither depends on
  the other.

## Acceptance criteria

- **A1** `git diff origin/main` in the registry touches only `schema/cg-extension.schema.json`: the removed
  `subcommands` block and the one-sentence description change; the file is valid JSON and a valid Draft 2020-12
  schema (`Draft202012Validator.check_schema`).
- **A2** Every `*/cg-extension.json` on cg-extensions `main` validates against the changed schema (the
  `validate.yml` script run locally with the schema from the PR branch instead of registry `main`).
- **A3** Against the changed schema: a v1 manifest and a v2 manifest that each carry `contributes.subcommands` fail,
  and the error names `subcommands`; the same v1 manifest without it validates; a v2 manifest with `commands`
  validates.
- **A4** `index.json` still validates against `index.schema.json` (unchanged files; checked for completeness).

## Questions for the owner

- **Q1** Do `"manifest": 1` manifests stay valid? **Proposed: yes.** cg 2.0 accepts v1 (`manifest.go`: 1..2), 9 of
  the 11 indexed extensions are v1 and need nothing v2 offers; only the `subcommands` key goes, from both versions.
- **Q2** What happens to third-party manifests still using `subcommands`? **Proposed: they fail schema validation
  from the merge on, with no deprecation window.** None is indexed today; cg 1.x keeps reading them (cg never reads
  the schema), cg 2.0 already ignores the key, so the only change is that authors' validation now reports it. The
  migration is already documented (consigliere `EXTENSIONS.md`: move to `commands` and `"manifest": 2`). The
  alternative, keeping it valid in v1 only, is in the analysis and not recommended.
- **Q3** Add a migration hint to the schema? **Proposed: one sentence on the `commands` description (S2)**, since
  the validator's error ("Additional properties are not allowed ('subcommands' was unexpected)") doesn't say what
  replaced it. Alternative: no text change, the schema only drops the block.
- **Q4** Where does this spec folder land? The registry has no `specs/` folder (its README: "the issue's agreement
  comment is the spec"), and nothing else changes in cg-extensions. **Proposed: a docs-only cg-extensions PR with
  the folder (`Refs #69`), so the agreed spec is kept as history like other items (cg-extensions README, Author).**
  Alternative: the folder stays on the branch only and the registry PR links it.
