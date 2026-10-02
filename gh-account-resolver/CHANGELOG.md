# Changelog

## 0.2.0

- **Changed:** routing now happens per `gh` call, at call time, instead of by rewriting the command text before it runs ([#6](https://github.com/mnemcik/cg-extensions/issues/6)). The hook moves from `PreToolUse` to `SessionStart`. At session start it puts a `gh` wrapper first on `PATH` through the session's `CLAUDE_ENV_FILE`; the wrapper works out the owner from each call's arguments and runs the real `gh` with that account's token. Fixes:
  - every `gh` after the first in a chained command, or after a `cd`, ran under the default account;
  - `gh repo clone OWNER/REPO` and other owners given as plain arguments were not recognised;
  - owners in shell variables (`-R $R`, loops) were not recognised;
  - `gh api repos/OWNER/…` was routed by the current directory instead of `OWNER`, which once posted a write under the wrong account.
- **Added:** owner resolution from `--repo=`, `-ROWNER/REPO`, `HOST/OWNER/REPO`, `GH_REPO`, `gh repo` arguments, GitHub URL arguments, `gh api` endpoints and `repo:`/`org:`/`user:`/`owner:` qualifiers, `--owner` (search, project), `--org` (secret, variable), and the `gh-resolved` or `upstream` remote before `origin`. URLs inside text flags such as `--body` are never used. Bare-name `gh repo clone|create|fork` uses the default account.
- **Added:** `gh` started by child processes (`xargs gh`, `bash -c`, scripts), subagents, background commands and the Monitor tool is routed too.
- **Added:** `tests/run.sh`, run in CI on macOS (bash 3.2, zsh) and Ubuntu (bash 5, zsh) against a fake `gh`.
- **Footprint change:** `PATH` now changes for this workspace's Claude Bash commands, through Claude Code's per-session env file, and the workspace gains an ignored `.claude/gh-account-resolver/` directory. Shell startup files, `~/.config/gh` and global `gh` state stay untouched.
- **Upgrade note:** restart running Claude sessions after updating; the wrapper is installed at session start.

## 0.1.0

- Initial release. `PreToolUse` hook for per-command `gh` account routing via `.claude/gh-account-map`, plus a CLAUDE.md documentation section. Fails open; zero global footprint.
