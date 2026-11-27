# Spec — #65: github-digest's skill becomes a cg-managed `skills` contribution

Issue: https://github.com/mnemcik/cg-extensions/issues/65 · Size **S** (plan: none) · Implements
mnemcik/consigliere#300 spec X2 and plan "Cross-repo" step 2 (`specs/gh-300-extension-skills/`), following #62's
spec ([`specs/gh-62-manifest-v2/spec.md`](../gh-62-manifest-v2/spec.md)) as the pattern.

## Analysis

**Problem (valid on `main` @ `b9710d0`).** `github-digest/cg-extension.json` is `"manifest": 1` and ships the skill
as two `templates` entries (`templates/skill/SKILL.md`, `templates/skill/gh-repo-watch.py` →
`.claude/skills/github-digest/`). As templates, the skill is the workspace's once copied: edits drift from the
extension, an update of an edited file is left pending, and the fetcher is installed without the execute bit, so
`SKILL.md` calls it through `python3 "$(git rev-parse --show-toplevel)/.claude/skills/github-digest/gh-repo-watch.py"`,
a workspace path that is wrong under any other skill target. cg 2.0's `skills` contribution (#300) manages the skill
instead: updates replace it, customisation goes in `SKILL.local.md`, listed `executables` are installed `0755`.

**Preconditions hold.** cg 2.0.0 is released (https://github.com/mnemcik/consigliere/releases/tag/v2.0.0,
2026-11-27, with its assets; installable with `cg update upgrade` or Homebrew), and the registry schema on `main`
accepts `skills` under `manifest: 2` (`schema/cg-extension.schema.json`, registry#31). So the issue's "merge only
after 2.0.0 is installable" condition is already met: the PR can merge as soon as it is reviewed. The companion move
for `live-runs` and `shopping` (#62) merged in #64.

**Recommendation.** Do X2 as written: move the folder to `skills/github-digest/` (its base name is the skill's name),
declare it under `skills` with `gh-repo-watch.py` as its executable, keep the target-file template a template, have
`SKILL.md` call the fetcher by `${CLAUDE_SKILL_DIR}` and carry the local-file block, bump to **0.3.0** (breaking:
requires cg 2.0), then bump the registry index.

**Alternative (not recommended).** Keep the `templates` entries and only bump to manifest v2 (or stay on v1, which
cg 2.0 still installs). Nothing breaks and cg 1.x users keep updates, but it leaves exactly the problem above, and
#300's agreed plan names this move as its cross-repo step 2.

**Overlap.** #31 (decided 2026-11-26, not implemented; branch `gh-31-digest-untrusted-notice` holds only its
analysis) edits other lines of the same `SKILL.md` (the untrusted-content notice, a request section, a check step)
and bumps github-digest to 0.2.1. #31's decision 4 already says it doesn't wait for #65 and, if #65 merges first,
edits the moved file. The two changes don't touch the same lines; whichever merges second rebases onto the other
(see Q4 for the version number).

## Changes

- **M1** `git mv github-digest/templates/skill github-digest/skills/github-digest` (both files, history kept;
  `gh-repo-watch.py` keeps its content). `github-digest/templates/github-digest-target.md` stays where it is.
- **M2** `github-digest/cg-extension.json`: `"manifest": 2`; the two skill `templates` entries removed;
  `"skills": [{ "src": "skills/github-digest", "executables": ["gh-repo-watch.py"] }]`; the
  `templates/github-digest-target.md` entry unchanged; `version` 0.2.0 → **0.3.0**. No `requires` field (a v2
  manifest already implies cg ≥ 2.0, as in #62).
- **M3** `SKILL.md`:
  - the local-file block `v1`, word for word from cg's skill template (`docs/templates/extension-skill/SKILL.md` on
    consigliere `main`), right after the frontmatter;
  - the *Inputs* line on the fetcher says it is `gh-repo-watch.py` in this skill's directory, written
    `${CLAUDE_SKILL_DIR}` below (Claude Code fills it in; another tool's agent uses the skill directory's path), and
    that cg installs it executable; the "cg installs templates without the execute bit" reason and the
    `git rev-parse --show-toplevel` path go;
  - both commands in *Process* become `"${CLAUDE_SKILL_DIR}/gh-repo-watch.py" OWNER/REPO …`, called directly; the
    Windows note stays: there, run it as `python "${CLAUDE_SKILL_DIR}/gh-repo-watch.py" …` (or `py`);
  - nothing else in the file changes (#31's lines are left to #31).
- **M4** `github-digest/tests/test_gh_repo_watch.py`: `SCRIPT` points at `skills/github-digest/gh-repo-watch.py`.
  No other test change.
- **D1** `github-digest/README.md`: the contribution table lists `skills` (`.claude/skills/github-digest/`:
  `SKILL.md` and `gh-repo-watch.py`, installed executable) and the `templates` row for the target file; a short
  *Customising* paragraph: cg manages the skill, put workspace rules in `.claude/skills/github-digest/SKILL.local.md`,
  an edit to the skill's own files is replaced on the next update (an uncommitted one stops it); *Requirements*
  gains "cg 2.0 or later"; the two fetcher examples call the installed script directly
  (`.claude/skills/github-digest/gh-repo-watch.py OWNER/REPO …`); the *Limits* link points at
  `skills/github-digest/SKILL.md`.
- **D2** `github-digest/CHANGELOG.md`, `## [0.3.0] — <merge date>`, under *Changed*: **(breaking) requires cg 2.0**;
  the skill is now managed by cg (manifest v2 `skills`): updates replace it, customise through `SKILL.local.md`, the
  fetcher is installed executable and called by the skill's directory. How to update: update cg on every machine that
  shares the workspace first (`cg update upgrade`, or `brew upgrade --cask cg`); if you edited
  `.claude/skills/github-digest/SKILL.md`, commit the edit (the update replaces a committed edit and says so; the
  old text stays in git history; it stops on an uncommitted one) and carry what you need into `SKILL.local.md`;
  then `cg extension update github-digest` and commit.
- **R1** Registry (mnemcik/cg-extensions-registry, its own PR, after this one, `Fixes mnemcik/cg-extensions#65`):
  the `github-digest` entry's `latestVersion` → 0.3.0 and its description ends "(gh 2.48+, cg 2.0+)" instead of
  "(gh 2.48+)". Nothing else in the index.

## Acceptance criteria

- **A1** The manifest validates against the registry schema on `main` (the `validate` job passes).
- **A2** `github-digest/tests` pass unchanged apart from M4 (CI on macOS, Ubuntu and Windows).
- **A3** On the released cg 2.0.0, in a scratch git workspace, installing from this branch
  (`cg extension install https://github.com/mnemcik/cg-extensions --path github-digest --ref gh-65-github-digest-skills`)
  writes `.claude/skills/github-digest/SKILL.md` (`0644`) and `gh-repo-watch.py` (`0755`) and
  `templates/github-digest-target.md`, prints no local-file-block warning (#300 S12b), and `cg extension list` shows
  the skill.
- **A4** #300 S40 end to end on cg 2.0.0: in a scratch workspace with 0.2.0 installed and committed (from a local
  clone whose default branch is then moved to this branch's head, since `update` reads the default branch),
  `cg extension update github-digest`
  - with no edits: succeeds, no "unowned" refusal and no pending entry, the files hold the new content and modes,
    the ledger records the skill;
  - with a committed edit to `SKILL.md`: succeeds and says the edit was replaced (#300 S30);
  - with an uncommitted edit: stops before writing, naming the file (#300 S31).
- **A5** The installed fetcher runs directly: `.claude/skills/github-digest/gh-repo-watch.py --help` exits 0, and a
  `--count-only` run against a small public repo succeeds.
- **A6** In Claude Code in the A3 workspace, the loaded skill shows the fetcher command with `${CLAUDE_SKILL_DIR}`
  replaced by the skill's absolute directory (checked once by hand, or with a headless run printing that line).
- **A7** `grep -rn "templates/skill\|show-toplevel" github-digest` finds only CHANGELOG history.

## Merge order

cg 2.0.0 is released and installable, so there is no hold: this PR merges when reviewed, the registry PR right after
it (R1). Each PR says `Fixes #65`; the first to merge closes the issue, as in #62 (accepted).

## Calls made in this spec (within X2)

- The folder is moved with `git mv`, not copied, so the file history follows it.
- No `allowed-tools` frontmatter is added: it would let the agent run the fetcher without asking, which is a new
  behaviour #300 asks reviewers to check, not part of this move.

## Questions for the owner (proposed answer each)

1. **Version:** 0.3.0 with *Changed (breaking): requires cg 2.0*, as #62 did for `live-runs` and `shopping`.
2. **How the skill calls the fetcher:** directly by `${CLAUDE_SKILL_DIR}` (X2), with one sentence saying it is this
   skill's directory for tools that don't fill it in, and the Windows `python` / `py` note kept. *Alternative:* keep
   `python3 "$(git rev-parse --show-toplevel)/.claude/skills/…"`; it also works, but only under the `claude` target
   and against X2.
3. **Edited 0.2.0 skills:** no migration help beyond the CHANGELOG text in D2 (commit, then move your rules to
   `SKILL.local.md`); cg's S30/S31 messages cover the rest.
4. **Order and version with #31:** neither waits for the other. If this merges first, #31's change edits
   `skills/github-digest/SKILL.md` and github-digest becomes **0.3.1** there instead of its agreed 0.2.1 (and reaches
   cg 2.x only, as #31's decision 4 already accepts); if #31 merges first, this stays 0.3.0 and rebases onto it. To
   be confirmed on #31 when it's implemented.
5. **Registry description:** append "cg 2.0+" in the existing parenthesis, "(gh 2.48+, cg 2.0+)" (R1), matching
   #62's "(cg 2.0+)".
