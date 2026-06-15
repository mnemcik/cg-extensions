# Changelog

All notable changes to this extension are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned

- `cg 1password get|whoami|item` — a thin `cg-1password` binary wrapping the `op`
  CLI, contributed as a `subcommands` entry.

## [0.1.0] - 2026-06-15

### Added

- Initial release. Content-only extension contributing:
  - `claude-md-sections` → `credentials-1password`: a pointer-style rule block
    that surfaces 1Password whenever credentials enter a session.
  - `notes` → `notes/credentials-1password-policy.md`: full credential-handling
    mechanics (JIT `op` retrieval, `op://` referencing + syntax limits, the
    Claude-Code-`op://`-resolution gotcha, alternatives, item creation, and
    1Password SSH-agent git auth).
