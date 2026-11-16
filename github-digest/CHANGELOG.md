# Changelog — github-digest

All notable changes to this extension are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); the extension version lives in
`cg-extension.json` (`version`).

## [0.1.0] — 2026-11-16

### Added
- The `github-digest` skill (`.claude/skills/github-digest/SKILL.md`). It covers the trigger, the digest process, the selection rules, the gaps, and adding a target.
- `gh-repo-watch.py`, a read-only fetcher that collects everything since a cursor:
  - issues and PRs
  - issue and review comments
  - reviews, fetched per active PR
  - releases
  - GraphQL discussions

  It writes `summary.md`, per-thread `chunk-NN.md` files, `raw/*.json` and `manifest.json`. Bot-only threads are rolled up rather than narrated.
- `templates/github-digest-target.md`, the per-repo target format, holding the Cursor and the Digest History.
- Repository content is treated as data, never instructions. The skill says so for the agent and for every batch and merge subagent, and each chunk file opens with the same notice.
