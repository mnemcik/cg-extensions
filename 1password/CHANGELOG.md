# Changelog

All notable changes to this extension are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned

- `cg 1password get|whoami|item` — a thin `cg-1password` binary wrapping the `op`
  CLI, contributed as a `subcommands` entry.

## [0.2.0] - 2026-10-14

### Added

- `hooks` → `PostToolUse` and `PostToolUseFailure`: `hooks/ssh-auth-hint.sh` (and the identical `hooks/ssh-auth-hint-on-failure.sh`). After a Bash command whose output shows git or ssh failing to authenticate (`Permission denied (publickey)`, `agent refused operation`, `fatal: Authentication failed for`, `fatal: could not read Username for`), it adds the 1Password remedy to Claude's context as `additionalContext`. The remedy no longer depends on Claude classifying the failure as credential-related and loading the note. On any other output it exits after one `grep`; without `jq` it does nothing.
- `tests/run.sh`: fixture hook payloads (matches, near-misses, malformed input, no `jq`, a 3 MB output), run in CI on macOS (bash 3.2), Ubuntu and Windows Git Bash.

### Changed

- The note's SSH section now tells the three causes of `Permission denied (publickey)` apart (app not running: `Connection refused`; locked: `The agent has no identities`; key in a non-default vault: keys listed but refused) and gives the literal `SSH_AUTH_SOCK=… ssh-add -l` probe for macOS and Linux, plus the Windows named pipe.
- The `CLAUDE.md` section's trigger now includes a git fetch/push/clone failing with an SSH authentication error.

### Upgrade note

Run `cg extension update 1password`, then restart running Claude sessions to be sure they pick up the new hooks.

## [0.1.1] - 2026-10-05

### Added

- The note now opens with YAML frontmatter (`title`, `category`, `tags`). Its tags include `ai-instructions`, the tag cg uses to mark notes that govern how Claude behaves, so the note can be found and reviewed with the rest of them.

## [0.1.0] - 2026-06-15

### Added

- Initial release. Content-only extension contributing:
  - `claude-md-sections` → `credentials-1password`: a pointer-style rule block
    that surfaces 1Password whenever credentials enter a session.
  - `notes` → `notes/credentials-1password-policy.md`: full credential-handling
    mechanics (JIT `op` retrieval, `op://` referencing + syntax limits, the
    Claude-Code-`op://`-resolution gotcha, alternatives, item creation, and
    1Password SSH-agent git auth).
