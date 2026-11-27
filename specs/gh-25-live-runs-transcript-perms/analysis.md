---
title: "Analysis — #25: live-runs transcripts readable by other users when CG_LIVE_DIR is writable by them"
created: 2026-11-27
item: "https://github.com/mnemcik/cg-extensions/issues/25"
size: full  # the analysis document's size; the item size in the repo's sense is proposed below (S)
verdict: needs clarification
---

# Analysis — #25: live-runs transcripts readable by other users when `CG_LIVE_DIR` is writable by them

Issue: https://github.com/mnemcik/cg-extensions/issues/25 · Size proposed: **S** (one check in `cg-live`, tests,
docs, a patch version) · Checked against `main` at `10ba73f`.

## Question

`cg live run` writes the full transcript of a headless run and the output of every shell command (secrets included)
to `$CG_LIVE_DIR`. When that directory can be written by another local user, that user can arrange to read the logs
or swap the `latest.*` links, although the docs say the logs are private. It affects users who point `CG_LIVE_DIR`
at a shared or world-writable directory; the default directory is not affected. This is a **"how"** item: the
problem is real (below) and the question is which fix.

## Current state (evidence)

**Current behaviour** (`main` `10ba73f`):

- The log directory gets mode `700` only when `cg live` creates it; an existing one keeps its mode
  (`live-runs/bin/cg-live:51-53`, since `24f2868`, part of #21). The commit message gives the reason: chmod on every
  start changed a directory set up on purpose (e.g. `755`), and a directory the user doesn't own (`/tmp`) made the
  run fail with "cannot create".
- File names are predictable: `<YYYYmmdd-HHMMSS>-<pid>-<label>.events.jsonl` / `.cmd.log` (`cg-live:55-57`).
- The files are opened with `( umask 077; : > "$events" && : > "$cmdlog" )` (`cg-live:58`). `umask` applies only to
  a file that is created; `: >` on an existing name truncates it, keeps its owner and mode, and follows a symlink.
  The run then appends to the same paths (`cg-live:68` `>> "$events"`; `cg-live-tee:41,44,46` `>>` / `tee -a`).
- `latest.events.jsonl` / `latest.cmd.log` are replaced with `ln -sfn` (`cg-live:59-60`); `cg live watch` follows
  them by default (`cg-live:157-160`).
- The docs promise privacy: `live-runs/README.md:40` ("private to you (the files are `600` …)"),
  `live-runs/notes/live-runs.md:22`, `cg-live:22-24`, CHANGELOG 0.1.0 ("logs are private (`700`/`600`)").
- Tests cover a created directory (`700`), file modes on fresh names (`600`) and an existing `755` directory keeping
  its mode (`live-runs/tests/run.sh:130-140`); nothing covers a directory others can write to or a pre-existing name.
  CI runs the suite on macOS and Ubuntu (`.github/workflows/validate.yml:125-134`), not Windows.

**Reproduced** (2026-11-27, macOS, bash 3.2, one user simulating the other side, fake `claude` as in the test
suite): with names pre-created in a `777` directory, the run's events file stayed `666` and held the transcript, and
the `cmd.log` name, a symlink, was followed, so the command output went to the link's target. A run on fresh names in
the same directory got `600` files. This confirms the issue's mechanism; the multi-user step itself was not run.

**Where it applies** (from the issue, mechanism confirmed above; platform defaults are `assumption (high)`, not
re-tested here): any directory another user can write to: a group-writable shared folder, or `/tmp` on macOS (sticky,
but macOS has no `protected_regular` / `protected_symlinks`). On Linux those sysctls, on by default in most
distributions, make the run fail with "cannot write logs" in a sticky `/tmp` instead. The default
`~/.cache/cg-live/` is created `700` and is not affected.

**Expected behaviour:** a run's logs are readable only by the user who started it, wherever `CG_LIVE_DIR` points, or
the run refuses to start with a message saying why; `latest.*` and `cg live watch` show only that user's runs.

**Unchanged:** the default directory, file names and layout, `cg live watch`, the result JSON on stdout and the
exit code, the umask `claude` and its tools run with, and an existing directory's mode (the reason for `24f2868`).

**Recon checked:**

- this repo: `live-runs/bin/cg-live`, `bin/cg-live-tee`, README, note, CHANGELOG, tests, CI workflow; `git log`
  of `cg-live` (only #21 and #52 touched it; `24f2868` is the change in question): problem present on `main`;
- other extensions in this repo for an existing "refuse an unsafe directory" helper: nothing found;
- open PRs in this repo and in consigliere for overlap (below);
- shell behaviour checked locally: `set -o noclobber` (bash 3.2) refuses an existing regular file or a symlink to a
  missing file, but **allows writing to an existing FIFO**; `mktemp -d` creates a `700` directory;
- external tools: none needed; the fix uses POSIX shell and `find -perm`.

## Validity

| Question | Answer | Evidence |
|---|---|---|
| Does the problem exist? | Yes | Reproduction above; `cg-live:53,58-60` |
| Is the expected behaviour right? | Yes: the README, note and CHANGELOG promise private logs | `README.md:40`, `notes/live-runs.md:22`, CHANGELOG 0.1.0 |
| Is it still current? | Yes, unchanged since `24f2868`; PR #64 doesn't touch `cg-live` | `git log -- live-runs/bin/cg-live`; `gh pr diff 64 --name-only` |
| Is it the right problem? | Yes, the cause is accepting a directory others can write to; the file mode is a symptom. Fixing only the file creation leaves `latest.*` swappable | `cg-live:59-60,157-160` |

**Verdict:** valid.

## Options

### Recommended — refuse a log directory that other users can write to

- **What:** before creating any file, `cg live run` first runs the ancestor check (step 3) on the physical path of
  the deepest part of `CG_LIVE_DIR` that already exists; then, when the directory is missing, creates every missing
  component with mode `700` (`( umask 077; mkdir -p "$dir" )`, instead of today's `mkdir -p` plus `chmod 700` on
  the leaf only, `cg-live:53`, which leaves new intermediate directories at the caller's umask); then:
  1. **resolves the log directory once** to its physical path (`cd -P "$dir" && pwd -P`) and uses only that path
     from then on: for the log files, the `latest.*` links, `CG_LIVE_CMD_LOG` (which `cg-live-tee` reopens on every
     shell command) and the `CG_LIVE_DIR` it passes to the tmux viewer (`cg-live:82`);
  2. **checks the resolved directory:** owned by the user, no group or other write bit;
  3. **checks every ancestor of the resolved path** up to `/` (again after `mkdir`; the components it created are
     the user's and `700`, so they pass): each one is **owned by the user or by root**, and either not writable by
     group or others or sticky (`/tmp`). Ownership matters because the owner of a directory can always rename or
     replace its entries (and add a write bit back); sticky only stops *other* users. With both, nobody but the user
     and root can rename or replace a path component between the check and the run's later writes.
  Otherwise it exits 2 without starting `claude`, with a message naming the path and why: for a directory the user
  owns, the fix is `chmod go-w <dir>`; for one the user doesn't own (e.g. `/tmp` itself), use a directory of their
  own (unset `CG_LIVE_DIR` for the default, or make e.g. `/tmp/<name>` with mode `700`). A check that can't be
  completed (an unreadable ancestor, a failing `find`) refuses too. The checks are portable shell: `[ -O ]`, and
  `find "$p" -prune \( -perm -020 -o -perm -002 \)` / `-perm -1000` (POSIX `-perm -mode`, same on BSD and GNU) on
  the already resolved path. The directory's mode is never changed, so the reason for `24f2868` holds: a `755`
  directory set up on purpose still works. As cheap defence in depth, the per-run files are created with
  `noclobber` (`set -C`, inside the creating subshell only), so a leftover or colliding regular file fails instead of
  being reused; it does not stop an existing FIFO, so it adds nothing once the directory check holds.
  `cg live watch` without a file argument runs the same checks before following `latest.*` (`cg-live:157-160`), so
  the viewer's default can't show another user's file; with an explicit file it reads what it is given. Tests: a `777`
  and a `775` directory, and a directory under a non-sticky `777` parent, are refused before `claude` runs and nothing
  is written; a `755` directory and a `700` directory under a sticky `1777` parent still work; a symlinked
  `CG_LIVE_DIR` is checked and used as its target; `watch` refuses an unsafe directory. An ancestor owned by another
  user needs a second uid, so CI can't test it: cover the ownership branch with a small function test or say it is
  untested. A missing two-level path under `umask 002` is created `700` at every level and accepted. Docs: README, note and the header comment say where the logs may
  live; CHANGELOG entry (telling users of a shared directory to check and delete old runs there); patch version.
- **Trade-off:** someone who uses a group-writable or world-writable directory today (including `/tmp` itself on
  macOS) gets a refusal after updating and has to change the directory or its mode. Covers pre-created files,
  symlinks, FIFOs, swapped `latest.*` and swapped path components with one check instead of hardening each write;
  residuals: ACLs and root (hidden constraints).
- **Wrong choice when:** a deliberately group-writable log directory shared by a team is a supported use. Nothing in
  the README or note suggests it is: both describe the logs as private.
- **Rabbit holes:** ACLs (macOS, Linux) can grant write without a mode bit; the check sees only mode bits (see
  hidden constraints). Don't try to inspect ACLs or group membership. Checking the path as typed instead of the
  resolved one: a symlinked `CG_LIVE_DIR` (or a link in an ancestor) that another user can replace would pass the
  check and be re-pointed later, because the tee and the viewer reopen files by path for the whole run; that is why
  step 1 resolves first and everything after uses the physical path.

### Alternative — a per-user private subdirectory when the directory is shared (runner-up)

- **What:** the same checks, but when the configured directory is writable by others (and its ancestors are safe),
  `cg live` uses `"$dir/cg-live-<uid>"` instead: created with `mkdir` (atomic, fails when the name exists, so it must
  then be owned by the user and `700`), holding the run files and `latest.*`; `cg live watch` maps the same way.
- **Trade-off:** `/tmp` on macOS and shared folders keep working without a refusal, at the cost of a second layout
  that users of a shared directory see (their logs are one level down), the same mapping in `watch`, and more code
  and tests in a security path.
- **Wrong choice when:** nobody actually needs a shared log directory; the README and note describe the logs as
  private, so a refusal with a clear message is enough.
- **Rabbit holes:** a leftover `cg-live-<uid>` someone else created first (must refuse, not reuse); uid naming on
  Windows.
- **Wins instead if:** the owner wants an existing `CG_LIVE_DIR=/tmp` (or a shared folder) to keep working after the
  update.

### Alternative — private per-run directory

- **What:** keep accepting any directory, but create each run's files inside a fresh `mktemp -d` directory
  (`<stamp>-<pid>-<label>.XXXXXX/`, mode `700`, created exclusively), so nobody else can pre-create or redirect them.
- **Trade-off:** works in a shared directory, but changes the file layout users and scripts see; `latest.*` in the
  shared directory can still be swapped, so `cg live watch` (default) can be pointed at another user's file and show
  its content (including terminal escape sequences) as if it were the run.
- **Wrong choice when:** the viewer's default (`latest.*`) is meant to be trustworthy, which it is today.
- **Rabbit holes:** making `latest.*` safe in a shared directory (it needs a private place for it, which is the
  per-user subdirectory above).
- **Wins instead if:** the file layout matters more than the viewer's default; in practice the per-user
  subdirectory above dominates it.

### Alternative — chmod `700` on every run again (revert `24f2868`)

- **What:** restore `mkdir -p "$dir" && chmod 700 "$dir" || die`.
- **Trade-off:** smallest diff, but silently changes the mode of a directory the user set on purpose, which is
  the bug `24f2868` fixed; a directory the user doesn't own fails with "cannot create", a misleading message.
- **Wrong choice when:** almost always; it trades one reported problem for another.

"Do nothing, fix the docs only" is not credible: the logs hold secrets and the docs, CHANGELOG and header all promise
privacy; a doc-only fix would leave a silent exposure for anyone who follows a reasonable "put logs in `/tmp`" habit.

## Hidden constraints

- **Reversibility:** a refusal is easy to relax later (e.g. allow group write behind an opt-in); a layout change is
  not. The recommendation is the reversible one.
- **Failure mid-operation:** the existing part of the path is checked before `mkdir -p`, and everything again on the
  resolved path before any log file is created and before `claude` starts. A refusal leaves no log file; an unsafe
  existing ancestor is refused before any directory is created. The directories `mkdir` creates are `700`; a refusal after
  `mkdir` (only possible through a race, since the existing part was checked first) leaves them behind, as today. `noclobber` failure also happens before `claude` starts (`die`, exit 2).
- **Security:** closes confidentiality (logs) and integrity of the viewer's default (`latest.*`). Not covered:
  ACL-granted write access, and root. Existing log files in an already-shared directory stay as they are; the
  CHANGELOG should tell affected users to check and delete old runs there. Root-owned ancestors (`/`, `/private`,
  `/tmp`) are trusted by design.
- **False positives:** on Linux systems with per-user groups and `umask 002`, a directory the user made themselves
  is `775`, so it would be refused although no one else is in the group. The message must give the one-line fix.
  Decision 2 is whether to refuse group write at all.
- **Platforms:** macOS and Linux are tested in CI. Windows (Git Bash / MSYS) reports synthesized modes; whether `[ -O ]`
  and `find -perm` give a usable answer there is **not verified** (`assumption (med)`: typically owned, `755`, so
  the check passes). live-runs has no Windows CI job; check on Windows while implementing or say it's untested.
- **Auto-update:** cg's own auto-update never installs a major version on its own (it records a notice instead,
  consigliere `internal/autoupdate/worker.go:88-89` and `major.go:15-18,92-105` at `origin/main`; an explicit `cg update upgrade` clears it,
  `cmd/update.go:131-132`), so users stay on cg 1.x until they upgrade.
- **Dependencies / sequencing:** PR https://github.com/mnemcik/cg-extensions/pull/64 (live-runs and shopping on
  manifest v2, `live-runs` 0.1.1 → 0.2.0) is open and held until cg 2.0.0 is released (release PR
  https://github.com/mnemcik/consigliere/pull/312, waiting on #318 and #324 there). It touches the same
  `live-runs/README.md`, `notes/live-runs.md`, `CHANGELOG.md` and the manifest `version`, but not `bin/cg-live` or
  the tests. #64 makes live-runs 0.2.0 require cg 2.0 (cg 1.x refuses to install it), so a fix that exists only as
  0.2.1 never reaches users who stay on cg 1.x (majors are never auto-installed), and it waits for the 2.0.0 release.
  A 0.1.2 fix before #64 reaches them sooner; #64 then rebases over the same three docs files and the version line.
  Decision 3 weighs this. The other open PRs
  (consigliere #318, #324, #312) don't touch live-runs.
- **Who else is affected:** users with a custom `CG_LIVE_DIR`. The registry index bump that follows #64 would carry
  the new version; no registry schema change.

## Open decisions

| # | Decision | Recommended answer | Status |
|---|---|---|---|
| 1 | Approach | Resolve the log directory once; refuse it when it isn't the user's or others can write to it, or when an ancestor isn't owned by the user or root, or is writable by others without being sticky; the same check in `cg live watch` for `latest.*`; never chmod it; `noclobber` on the per-run files as defence in depth. Runner-up: a per-user subdirectory in a shared directory | open |
| 2 | Refuse group-writable directories too, or only world-writable ones? | Group-writable too (any other group member can do the same as with `/tmp`); the message gives the fix for the case (`chmod go-w` for the user's own directory, a directory of their own otherwise) | open |
| 3 | When does it ship? | After #64 merges (post cg 2.0.0), as live-runs 0.2.1: the release is in its last steps and exposure needs a non-default, shared `CG_LIVE_DIR`. Cost: users who stay on cg 1.x never get the fix. The alternative is a 0.1.2 before #64 (reaches cg 1.x users now; #64 rebases over three docs files and the version) | open |
| 4 | Size | S: one check, tests, docs; no plan file ("plan: none") | open |
| 5 | Windows | A check that can't be completed refuses (fail closed); state in the PR whether it was checked on Windows; no new Windows CI job in this item | open |

## Review

**Review 1** — `specs/gh-25-live-runs-transcript-perms/analysis.md` @ content hash `72a0702` (uncommitted) · 2026-11-27
- Reviewers: doc-reviewer (builder check, claim check, missed option, hidden constraints, governing rules)
- Tests: n/a (analysis); ancestor/symlink check prototyped in a scratch directory on macOS after the review
- Findings: 0 blocker, 3 should-fix, 2 nit → fixed: path components and symlinks not covered (resolve once, check ancestors, use the resolved path everywhere); 0.2.1 never reaching cg 1.x users (decision 3 now weighs it); per-user subdirectory added as runner-up; size field clarified; refusal message for a directory the user doesn't own; owner's: none; rejected: none
- Builder questions: 5 → answered in the text: ancestors and symlinks (step 1–3), when it ships (decision 3), group-writable (decision 2); minor (my call): `set -C` only in the creating subshell, FIFO limitation stated; a check that can't complete refuses (decision 5)
- Verified true: all line citations; `24f2868`'s reasons; `: >`/umask/noclobber semantics; `find -H -prune -perm` portability; PR #64 file list; no private data, class-level description
- Not verified: Windows Git Bash behaviour; the multi-user step (simulated as one user)

**Review 2** — same file @ content hash `eba170e` (delta from `72a0702`) · 2026-11-27
- Reviewers: doc-reviewer (delta; same lenses)
- Findings: 0 blocker, 1 should-fix, 2 nit → fixed: ancestors must also be owned by the user or root (the owner of a component can swap it even under a sticky parent); refusal no longer claimed to leave nothing when `mkdir -p` ran first (existing ancestors checked before it); decision 2 wording; owner's: none; rejected: none
- Builder questions: 2 → minor (my call): `cg live watch` runs the same checks for its default `latest.*`; root-owned ancestors trusted explicitly
- Regression: round-1 findings 2–5 resolved; 1 resolved with the ownership rule
- Verified true: cited lines; PR #64's cg 2.0 requirement; cg auto-update never installs a major (consigliere `cmd/update.go`)
- Not verified: `find -perm -1000` on GNU (BSD checked); Windows

**Review 3** — same file @ content hash `4e7023b` (delta from `eba170e`) · 2026-11-27
- Reviewers: doc-reviewer (delta; same lenses)
- Findings: 0 blocker, 1 should-fix, 1 nit → fixed: directories created by `mkdir -p` were left at the caller's umask and not rechecked (now created `700` at every level, ancestors checked on the resolved path after `mkdir`, refusal leftovers restated, test added); auto-update citation moved to `internal/autoupdate/major.go` (checked at consigliere `origin/main`); owner's: none; rejected: none
- Builder questions: 1 → answered in the text: ancestors checked on the physical path (deepest existing part before `mkdir`, the full resolved path after)
- Regression: round-2 findings resolved (ownership rule, decision 2 wording, `watch` default, root trusted); leftover-directory nit superseded by the fix above
- Not verified: Windows; `find -perm` on GNU

**Review 4** — same file @ content hash `f5debd5` (delta from `4e7023b`) · 2026-11-27
- Reviewers: doc-reviewer (delta; same lenses)
- Findings: 0 blocker, 0 should-fix, 2 nit → fixed: auto-update citation adds `worker.go:88-89`; refusal-leftover wording; **outcome: clean**
- Regression: round-3 findings resolved
- Not verified (all rounds): Windows Git Bash behaviour of `[ -O ]` / `find -perm`; GNU `find -perm -1000` (POSIX; BSD checked); the multi-user step (simulated as one user)

## Verdict

**needs clarification**: the problem is valid and the recommendation reviewed clean; the five open decisions are the
owner's, and nothing is implemented until they are answered and the spec is agreed.

## Q→A log

- (none yet)
