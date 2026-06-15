# Changelog

All notable changes to this extension are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this extension
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Versions
track the `version` field in `cg-extension.json` (subdir extensions in the
[`cg-extensions`](https://github.com/mnemcik/cg-extensions) monorepo are
addressed by manifest version, not per-member git tags).

## [0.1.0] - 2026-06-15

### Added

- Initial release. Content-only extension contributing:
  - `claude-md-sections` → `spec-driven-development`: a pointer-style trigger
    block that fires only for greenfield software builds wanting a PRD/spec, and
    explicitly excludes brownfield/existing-codebase, research, analysis, event,
    and documentation work.
  - `notes` → `notes/spec-driven-development.md`: the full methodology — four
    ground rules, three phases (PRD → specs → milestone implementation), the
    spec-authoring step list with applicability flags, and prompt templates.
