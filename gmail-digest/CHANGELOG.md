# Changelog — gmail-digest

All notable changes to this extension are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); the extension version lives in
`cg-extension.json` (`version`).

## [0.2.0] — 2026-10-13

### Added
- Gmail search gotchas: thread search caps each thread's messages, and `resultCountEstimate` under-reports.
- A step that reconciles the target's Digest History with the digest folders on disk.
- **Large backlogs:** paging to disk with an independent coverage audit, and two strategies: filter and read in chunks, or fan out to subagents.
- `templates/gmail-digest-target.md`: a `Last Message Epoch` column in the Digest History table, which the workflow reads and writes.

### Changed
- `notes/gmail-digest-workflow.md`: a digest selects messages with `is:unread`, not `after:<epoch>`. `after:` matches per message but returns whole threads, so long threads brought their already-digested history back. Messages older than the last epoch are still dropped, and marking messages read is now the final step.
- Output files are `batch-NN.md`, and `analysis.md` carries the workspace's note metadata, including areas.

## [0.1.0] — 2026-06-16

### Added
- Initial extension: Gmail digest shortcut.
- `claude-md-sections` → `gmail-digest`: trigger rule ("check/digest X updates" → digest workflow, skip project gate, keep worktree gate).
- `notes/gmail-digest-workflow.md`: the digest process — per-target file, `after:<epoch>` incremental sync, the `label:`-name-not-ID gotcha, output structure, history tracking. Generalized from a personal workflow note (`cg worktree` subcommands; no personal targets).
- `templates/gmail-digest-target.md`: target-file skeleton.
