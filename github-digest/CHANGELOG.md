# Changelog — github-digest

All notable changes to this extension are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); the extension version lives in
`cg-extension.json` (`version`).

## [0.1.1] — 2026-11-16

### Fixed
- **Busy repos lost most of their threads.** GitHub sorts and filters the issue list on an index that can lag the `updated_at` it returns, so a page can hold an item stamped days ahead of its place. The keyset advanced to the page's newest `updated_at` and jumped past everything in between. On `gastownhall/gascity` a 14-day window returned 266 of 777 threads, and a 7-day window 273 of 344. The next `since` is now the 10th-newest `updated_at` on the page (at most half the page), so up to nine such items per page can't move it. The same tolerance applies inside a stalled second: the page-number read counts the second as left only once 10 items on a page are past it, so one out-of-place item in a bulk-updated second can't cut the read short. Stamps older than the cursor don't count towards the 10. When most of a page is older than the cursor, the second is read by page number, which costs extra requests but loses nothing. Counts now match GitHub search. Repos with under 100 updated threads per window were not affected, and the comment lists were complete.

### Changed
- The skill explains that `orphaned_events` can also be threads the lagging index left out of the list, and says to name them in Data Caveats and fetch them by number when they matter.

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
