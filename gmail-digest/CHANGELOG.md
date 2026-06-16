# Changelog — gmail-digest

All notable changes to this extension are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); the extension version lives in
`cg-extension.json` (`version`).

## [0.1.0] — 2026-06-16

### Added
- Initial extension: Gmail digest shortcut.
- `claude-md-sections` → `gmail-digest`: trigger rule ("check/digest X updates" → digest workflow, skip project gate, keep worktree gate).
- `notes/gmail-digest-workflow.md`: the digest process — per-target file, `after:<epoch>` incremental sync, the `label:`-name-not-ID gotcha, output structure, history tracking. Generalized from a personal workflow note (`cg worktree` subcommands; no personal targets).
- `templates/gmail-digest-target.md`: target-file skeleton.
