# gh-account-resolver

A Consigliere extension that routes every `gh` call in a Claude Code session to the right logged-in `gh` account, so parallel sessions don't fight over the globally active account.

## Problem

`gh auth switch` writes shared state to `~/.config/gh/hosts.yml`. When several sessions run in parallel, that state drifts and commands run under the wrong account, which fails with `Could not resolve to a Repository`. A write can also land under the wrong identity.

## Mechanism

A `SessionStart` hook puts a small `gh` wrapper first on `PATH` for that session only. On every call, the wrapper works out which repo owner the call is about, looks it up in `.claude/gh-account-map`, and runs the real `gh` with `GH_TOKEN` set to that account's token. The token is read from the keyring with `gh auth token --user <account>` at call time. It never appears in a command line or in the transcript.

How the wrapper gets onto `PATH`:

- The hook creates `.claude/gh-account-resolver/bin/gh`, a symlink to the installed hook script. The directory ignores itself in git (its own `.gitignore` contains `*`).
- The hook adds one guarded line to the session's `CLAUDE_ENV_FILE`. Claude Code applies that file to every Bash command in the session: subagents, background commands, the Monitor tool, and child processes such as `xargs gh`, `bash -c` and scripts. The line is written once and only prepends the directory when it isn't already on `PATH`, because Claude Code reuses the file across resume and compact.

Because routing happens when `gh` actually runs, chained commands, a preceding `cd`, shell variables, loops and commands touching several owners all get the right account per call.

### How the owner is found

First match wins:

1. `-R` / `--repo` / `--repo=` / `-ROWNER/REPO` (`HOST/OWNER/REPO` gives `OWNER`); `--owner` for `gh search` and `gh project`; `--org` / `-o` for `gh secret` and `gh variable`.
2. `GH_REPO`.
3. The repo argument of `gh repo clone|view|fork|edit|delete|archive|unarchive|sync|set-default|create|list`. A bare name with no slash for `clone`, `create` or `fork` means the logged-in user's repo, so it goes to the default account regardless of the current directory.
4. A `github.com` URL given as an argument. URLs inside text flags (`--body`, `-t`, `-m`, `--notes`, `-f`/`-F`/`--field`, `--jq`, `--template`, `-H`, labels and branch names) are never used.
5. For `gh api`: the `repos/OWNER/…`, `orgs/OWNER` or `users/OWNER` endpoint (also as a full `api.github.com` URL), then a `repo:` / `org:` / `user:` / `owner:` qualifier, including inside `-f q=…`. `{owner}` placeholders count as no owner, so the current directory decides, as it does for gh.
6. For `gh search`: a qualifier in the query.
7. The current directory's git remote: the `gh-resolved` base, else `upstream`, else `origin`.

### What passes straight through

- A call that already sets `GH_TOKEN` or `GITHUB_TOKEN` (an explicit pin).
- `gh auth`, `config`, `alias`, `extension`, `help`, `version`, `completion`, and bare `gh`.
- No owner found, an owner not in the map, or an owner mapped to the default account.

### Fails open

Anything unexpected runs the real `gh` unchanged: a missing or malformed map, a failed token fetch, an unparseable call. The wrapper never uses `set -e`, turns off tracing first so a caller's `set -x` can't print the token, and runs on macOS `/bin/bash` 3.2. It skips every resolver directory on `PATH` when looking for the real `gh`, so nested sessions from two workspaces can't loop.

### Footprint

Nothing in your shell setup, `~/.config/gh` or global `gh` state changes, and your own terminal is unaffected. `PATH` changes only for this workspace's Claude Bash commands, through Claude Code's own per-session file under `~/.claude/session-env/<session-id>/`. The workspace gains the ignored directory `.claude/gh-account-resolver/`.

### Limits

- `gh` called by absolute path (e.g. `/opt/homebrew/bin/gh`) is not routed.
- Hooks' own processes don't see the session's `PATH`, so `gh` inside other hooks is not routed.
- Sessions that were already running when you installed or upgraded keep the old behaviour until they restart.
- After the extension is removed, the leftover `bin/gh` symlink points nowhere, and the shell falls back to the real `gh` on the default account. Delete `.claude/gh-account-resolver/` to clean up.

## Install

```
cg extension install cg/gh-account-resolver      # from the registry
cg extension install <path-or-git-url>           # local / direct
```

Restart running Claude sessions afterwards; the hook runs at session start.

## Configure

Create `.claude/gh-account-map` (workspace-local user config; not shipped by this extension):

```
default = mnemcik
idellabv     = mnemcik-work
Visma-Idella = mnemcik-work
```

One `owner = account` per line. `default` names the globally active account, which needs no routing. Owner match is case-insensitive; `#` starts a comment; CRLF line endings are fine. Add a line to route a new org; no code change.

## Contributes

- A `SessionStart` hook (`hooks/resolve.sh`), which is also the `gh` wrapper.
- A CLAUDE.md section documenting the routing behaviour and map format.

## Tests

`tests/run.sh` runs the routing rules, pass-through and fail-open cases, install idempotence and the loop guard against a fake `gh`, under bash and zsh. It never calls the real `gh`. CI runs it on macOS (bash 3.2, zsh) and Ubuntu (bash 5, zsh).
