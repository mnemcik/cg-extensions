# github-digest

A Consigliere extension that digests a GitHub repo's activity straight from the GitHub API, so you can follow an open-source project without its notification email.

## Problem

Following a busy repo through GitHub notification email has three problems:

- **The inbox floods**, and the mail only covers what GitHub chose to notify you about.
- **Mail clients make it worse.** Gmail search, for example, caps each thread at a few messages and estimates counts badly.
- **The digest has to manage unread state** just to know what it has already covered.

## Mechanism

Each watched repo has a **target file**, `notes/github-digest-targets/<slug>.md`. It holds a **cursor**: the timestamp the next digest starts from.

On "digest <slug>", the skill does five things:

1. Runs the fetcher for everything updated since the cursor: issues and PRs, comments, review comments, reviews, releases and discussions.
2. Groups the activity per thread into chunks of about 60k characters.
3. Rolls up threads with no human comment or review, such as stale-bot marks, CI and label-only changes.
4. Reads the chunks, fanning out to subagents when the window is large.
5. Writes `notes/<slug>-digest-YYYY-MM-DD/analysis.md` and advances the cursor.

There is no mark-as-read step and no subscription; the cursor is the only state.

The trigger is the skill's own description. The extension adds **nothing to CLAUDE.md**.

| Contribution | What |
|---|---|
| `skills` | `.claude/skills/github-digest/`: `SKILL.md`, the skill (trigger, process, selection rules, gaps), and `gh-repo-watch.py`, a read-only fetcher that uses `gh` and only the Python standard library, installed executable |
| `templates` | `templates/github-digest-target.md`: the per-repo target format |

### Customising

cg manages the skill: `cg extension update` replaces its files with the extension's version. Put your workspace's own rules in `.claude/skills/github-digest/SKILL.local.md`, which the skill reads and cg never touches. An edit to the skill's own files is replaced on the next update (the old text stays in git history); an uncommitted edit stops the update until you commit or discard it. With `skills.targets` naming `agents` in `.cg.json`, the same files are also installed under `.agents/skills/github-digest/`. The skill is written for Claude Code: another tool must read `${CLAUDE_SKILL_DIR}` in it as the skill's directory.

## Usage

```text
watch gastownhall/gascity          → creates notes/github-digest-targets/gascity.md
digest gascity                     → or "check gascity updates", or /github-digest gascity
```

The fetcher on its own, from the workspace root:

```sh
.claude/skills/github-digest/gh-repo-watch.py OWNER/REPO --since 2026-11-13T00:00:00Z --out /tmp/x --count-only
.claude/skills/github-digest/gh-repo-watch.py OWNER/REPO --since 30d --out /tmp/x
```

`--since` accepts an ISO time, a Unix epoch, or `Nd`. `--lookback Nd` (default `14d`) sets how far before `--since` the issue list is also read, to catch threads GitHub's lagging index leaves out. The run prints its manifest, and the next run's `--since` is `cursor_out`. The fetcher deletes any existing `chunk-*.md` in `--out` before writing, so use a scratch directory per run.

## Requirements

- cg 2.0 or later.
- Claude Code: the extension ships a Claude Code skill, installed under `.claude/skills/` by default.
- `gh` 2.48 or later (for `gh api --slurp`), authenticated. Public repos work with any account.
- Python 3.9+, standard library only.
- On Windows, run the fetcher as `python <path>` (or `py <path>`), since Windows doesn't use the execute bit. All I/O is explicit UTF-8.

## Limits

- **Commits pushed straight to the default branch without a PR are not fetched.**
- **Some activity is not covered:** reactions, project-board moves, and timeline events such as labelled or assigned.
- **Discussions are read only partly:** the last 50 comments, with up to 20 replies each. Comment edits that don't bump the discussion's `updatedAt` are missed.

This is a summary. The full list, including the stalled-second and open-bot-PR cases, is under **Not covered** in [`skills/github-digest/SKILL.md`](skills/github-digest/SKILL.md).

## Coming from `gmail-digest`

If you digested a repo through `gmail-digest`, you can move it here without a gap:

1. Move its target file to `notes/github-digest-targets/`.
2. Set Cursor to the last digest's Last Message Epoch. `--since` accepts an epoch.
3. Turn off the repo's notification email.

The `gmail-digest` trigger rule also matches "digest X", and it maps that to Gmail with no exception for GitHub targets. With both extensions installed, which one runs isn't guaranteed. To be sure, invoke `/github-digest <target>` explicitly, or remove `gmail-digest` if you no longer digest anything from Gmail.
