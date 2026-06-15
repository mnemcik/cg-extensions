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
  - `claude-md-sections` → `voice-trigger`: a pointer-style rule that loads the
    workspace's `VOICE.md` before drafting outbound text (Slack, email, Jira,
    PR), and skips it for read/summarize tasks.
  - `templates` → `templates/VOICE.md`: a skeleton style guide (register per
    channel, language conventions, punctuation quirks, vocabulary signals,
    greetings/closings, audience-stripping, drafting checklist) for the user to
    copy to the workspace root and personalise. No actual voice content ships.
