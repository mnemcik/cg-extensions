# Changelog — github-digest

All notable changes to this extension are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); the extension version lives in
`cg-extension.json` (`version`).

## [0.3.0] — 2026-11-28

### Changed
- **(breaking) Requires cg 2.0.** The manifest is v2, and the skill is a cg-managed `skills` contribution instead of two `templates` entries; cg 1.x refuses to install it. `cg extension update` now replaces the skill's files with the extension's version. Customise the skill in `.claude/skills/github-digest/SKILL.local.md`, which the skill reads and cg never touches.
- The fetcher is installed executable, and the skill calls it directly from its own directory (`"${CLAUDE_SKILL_DIR}/gh-repo-watch.py"`) instead of through `python3` and the workspace path. On Windows it still runs through `python` or `py`.
- **How to update:** update cg on every machine that shares the workspace first (`cg update upgrade`, or `brew upgrade --cask cg` for a Homebrew install). If you edited `.claude/skills/github-digest/SKILL.md`, commit the edit (the update replaces a committed edit and says so, and the old text stays in git history; it stops on an uncommitted one) and carry what you need into `SKILL.local.md`. Then run `cg extension update github-digest` and commit.
- The fetcher command changed, so a permission rule written for the old `python3 "$(git rev-parse --show-toplevel)/…"` form no longer matches; add one for the new path if you want to skip the prompt.

## [0.2.0] — 2026-11-17

### Added
- **Threads the issue list leaves out are found.** GitHub's index behind `issues?since=` can lag a thread's real `updated_at` for weeks, so a thread updated in the window could be missing from the digest; with no comment in the window it was lost for good (on `gastownhall/gascity`, 6 of 344 threads in 7 days; open threads up to 60 days behind). Four sources now add them: a lookback read of the issue list (`--lookback Nd`, default `14d`), a sweep of all open threads, a sweep of closed PRs sorted by update, and reading the thread behind every orphan comment by number. A thread that is gone (HTTP 404/410) or redirects to another repository is recorded with its reason in `closed_pr_fetch_failed` or `orphan_fetch_failed`, and the run continues; any other failed read by number (rate limit, server or auth error) ends the run like a failed list read, so no thread is lost to a transient error. Each found thread is listed in the new manifest field `found_outside_list` by source, and the skill names them in Data Caveats. On gascity this costs about 41 more list requests per run.
- `pre_cursor_unverified_seconds` and `lookback_days` in the manifest. An unverified stalled second before the cursor (from the lookback read) is reported there and doesn't hold the cursor.

### Changed
- Orphan comments are narrated with their thread instead of only counted; `orphaned_events` now lists only comments whose thread couldn't be read even by number, and the run continues.
- The skill's *Not covered* names the remaining gap (closed issues with only invisible changes before the lookback; closed PRs before it whose only activity is a review body), and its `stalled_seconds` text distinguishes tie seconds from pages stamped before the cursor.

### Fixed
- **Busy repos lost most of their threads.** GitHub sorts and filters the issue list on an index that can lag the `updated_at` it returns, so a page can hold an item stamped days ahead of its place. The keyset advanced to the page's newest `updated_at` and jumped past everything in between. On `gastownhall/gascity` a 14-day window returned 266 of 777 threads, and a 7-day window 273 of 344. The next `since` is now the 10th-newest `updated_at` on the page (at most half the page), so up to nine such items per page can't move it. The same tolerance applies inside a stalled second: the page-number read counts the second as left only once 10 items on a page are past it, so one out-of-place item in a bulk-updated second can't cut the read short. Stamps older than the cursor don't count towards the 10. When most of a page is older than the cursor, the second is read by page number, and the cursor then advances from the page that ended the read (or the fetch stops, when that read reached the end of the list), so it costs a few extra requests, loses nothing, and doesn't crawl through a long gap one second at a time. Counts now match GitHub search. Repos with under 100 updated threads per window were not affected, and the comment lists were complete.

## [0.1.0] — 2026-11-16

### Added
- The `github-digest` skill (`.claude/skills/github-digest/SKILL.md`). It covers the trigger, the digest process, the selection rules, the gaps, and adding a target.
- `gh-repo-watch.py`, a read-only fetcher that collects everything since a cursor:
  - issues and PRs
  - issue and review comments
  - reviews, fetched per active PR
  - releases
  - GraphQL discussions

  It writes `summary.md`, per-thread `chunk-NN.md` files, `raw/*.json` and `manifest.json`. Threads with no human comment, review, open or close in the window are rolled up rather than narrated, bot comments collapse to one count line, and a thread longer than a chunk is split.
- **Keyset pagination** for the three since-windowed lists. Requests run oldest first, and each request's `since` is the newest `updated_at` already seen, so a deletion mid-run can't skip an item. A second with 100 or more items falls back to page numbers, verified by re-reading until two reads agree. Those seconds are listed in `stalled_seconds`. If the reads never agree, the cursor is held before the second (`unverified_seconds`).
- Offline unit tests (`tests/`), run in CI on macOS, Ubuntu and Windows.
- `templates/github-digest-target.md`, the per-repo target format, holding the Cursor and the Digest History.
- Repository content is treated as data, never instructions. The skill says so for the agent and for every batch and merge subagent, and each chunk file opens with the same notice.
