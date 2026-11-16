---
name: github-digest
description: Digest a watched GitHub repo's activity since the last digest, read straight from the GitHub API (no notification email needed). Use when the user asks to "digest X", "check X updates", "what's new in X" or "catch up on X" and X has a target file in notes/github-digest-targets/, or invokes /github-digest <target>. Also use to add a new repo to watch ("watch owner/repo").
---

# GitHub Digest

Digest a public GitHub repo by querying its activity since a saved cursor, then write an analysis note. You don't need to watch the repo or receive notification email. The **cursor in the target file is the only state**.

## Inputs

- **Target:** `notes/github-digest-targets/<slug>.md`, one per watched repo. It holds the repo, the **Cursor** (an ISO timestamp, the next run's `--since`), domain context for the analysis, and the Digest History table. New targets start from `templates/github-digest-target.md`.
- **Fetcher:** `gh-repo-watch.py`, in this skill's directory. It is read-only, needs `gh` (authenticated) and Python 3.9+, and has no other dependencies.

If the user names a repo that has no target, offer to create one (see *Adding a target*), not to run without one.

## Process

1. **Work in a session worktree.** If the workspace uses them (Consigliere: `cg worktree create digest-<slug>-<YYYY-MM-DD>`), create one before writing anything. A digest is a recurring reference activity, so it needs no project.
2. **Read the target file**: repo, Cursor, domain context, history. Check the history table against the `notes/<slug>-digest-*/` folders on disk, and backfill any missing row.
3. **Size the window.** `<out>` is a scratch directory outside the repo (the session scratchpad, if there is one), because the raw corpus is input, not a note.
   ```sh
   python3 .claude/skills/github-digest/gh-repo-watch.py OWNER/REPO --since <cursor> --out <out> --count-only
   ```
   This prints thread counts for issues and PRs only. If the target has no cursor yet, ask the user for a starting window (`30d`, a date, or "from now"), and give them a `--count-only` figure for it.
4. **Choose a strategy from the size.** Count **signal threads**, the ones a human touched.
   - **≲ 300:** read every chunk yourself.
   - **Larger:** tell the user the size first. Then fan out: one subagent per ~25k-token chunk, each given the target's domain context and the per-entry format, writing `batch-NN.md`. Then merge.
   - **Very large** (thousands of threads): offer a narrower window instead.
5. **Fetch:**
   ```sh
   python3 .claude/skills/github-digest/gh-repo-watch.py OWNER/REPO --since <cursor> --out <out>
   ```
   It writes the following files:
   - `summary.md`: counts, releases, merged PRs, and the list of rolled-up bot-only threads
   - `chunk-NN.md`: per-thread text, about 60k characters each, holding the opening post when the thread is new plus every comment, review and review-line comment in the window, oldest first
   - `raw/*.json`: the unmodified API results
   - `manifest.json`: `cursor_in`, `cursor_out`, and the thread numbers in each chunk
6. **Read** `summary.md`, then every chunk, with the file-read tool (not `cat`). Write one `batch-NN.md` per chunk into `notes/<slug>-digest-YYYY-MM-DD/`.
   - **Coverage check:** the thread numbers in `manifest.json` minus those in your batch files should be empty, or explained (a thread folded into a sibling on purpose).
7. **Write `analysis.md`** in the same folder. Use the workspace's note frontmatter (category, tags, **areas**), plus `source: GitHub API (github-digest)`, `period_covered`, `cursor_in` and `cursor_out`. Sections:
   1. **Executive Summary**: the 3–5 things that matter
   2. **Timeline**: a dated table of notable events
   3. **Key Themes**
   4. **Items Needing Attention**: open bugs, security, blockers
   5. **Data Caveats**: what was rolled up, truncated or not covered
8. **Advance the cursor.** Set the target's **Cursor** to `manifest.cursor_out` and add a Digest History row: date, location, period, thread counts, cursor out.
9. **Index** the `analysis.md` in the workspace's notes index (`notes/INDEX.md`), if it has one.

## How the fetcher selects

- **Endpoints:**
  - `issues` (issues and PRs), `issues/comments` and `pulls/comments`, each with `since`, `sort=updated`, `direction=asc`.
  - `pulls/{n}/reviews`, called once per PR active in the window, because reviews have no `since` filter.
  - `releases`, filtered on `published_at`.
  - GraphQL `discussions`, ordered `UPDATED_AT DESC` and paged back to the cursor.
- **What `since` means.** GitHub's `since` filters on `updated_at`, not creation, and the docs don't say whether the boundary is inclusive. Everything is therefore re-filtered `> since` client-side.
- **`cursor_out` is the time the run started,** so windows overlap slightly and never leave a gap.
- **What can show up twice.** A comment created before the window but edited inside it is marked `(edited; created before window)`. A thread updated only by a state or label change gets a placeholder line.
- **Signal threads.** A thread is signal if a human acted in the window: opened it, commented or reviewed, or closed or merged it. Bot-only threads (stale marks, CI, dependabot) are listed in `summary.md` but not narrated. Bot logins match `BOT_RE` in the script: a `[bot]` suffix, dependabot, renovate, github-actions, codecov, copilot.
- **Caps.** Opening posts are capped at 3,000 characters and each comment or review at 2,000, with HTML comments stripped. Follow the thread URL when a truncated body matters.
- **Cost.** A busy repo uses a few hundred of the 5,000 per hour REST budget, mostly the per-PR review calls.

## Not covered

- **Commits pushed straight to the default branch without a PR.** If a repo works that way, add `gh api 'repos/O/R/commits?since=<cursor>'` by hand and say so in Data Caveats.
- **Reactions, project-board moves, and timeline events** such as labelled, assigned or cross-referenced.
- **Discussion comments beyond the last 50 per discussion, or the last 20 replies per comment.**

## Adding a target

When the user asks to watch `owner/repo`:

1. Copy `templates/github-digest-target.md` to `notes/github-digest-targets/<slug>.md`.
2. Fill in the repo, What This Tracks, and Domain Context. Ask the user what they care about, if it isn't clear.
3. Run `--count-only` for `30d` and record the volume under Typical volume.
4. Leave Cursor unset until the first digest, which decides the starting window with the user.

After that, the user can turn off GitHub notification email for the repo (Watch → *Participating and @mentions*). The digest no longer depends on it.
