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

1. `-R` / `--repo` / `--repo=` / `-ROWNER/REPO` (`HOST/OWNER/REPO` gives `OWNER`); `--owner` for `gh search` and `gh project`; `--org` / `-o` for `gh secret` and `gh variable`; `--org` for `gh repo fork` (the fork's new owner).
2. `GH_REPO`.
3. The first repo argument containing a slash for `gh repo clone|view|fork|edit|delete|archive|unarchive|sync|set-default|create|list`. Without one, the target belongs to the logged-in user (a bare name for `clone`, `create` or `fork`; no name for `list` or `create --source=.`), so it goes to the default account regardless of the current directory. `gh repo list OWNER` names the owner directly.
4. A `github.com` URL given as a positional argument.
5. For `gh api`: the `repos/OWNER/…`, `orgs/OWNER` or `users/OWNER` endpoint (also as a full `api.github.com` URL), then a `repo:` / `org:` / `user:` / `owner:` qualifier in a search query: the endpoint's `?q=`, or a `q=`/`query=` field (except for `gh api graphql`, where `query=` is GraphQL text). `{owner}` placeholders count as no owner, so the current directory decides, as it does for gh.
6. For `gh search`: a qualifier in the query.
7. The current directory's git remote: the `gh-resolved` base (or the `OWNER/REPO` it records), else `upstream`, else `origin`.

**Flag values are never read as owners.** Any flag outside a short list of known value-less flags (`--web`, `--squash`, `--private`, …) is assumed to take a value, and that value is skipped: bodies, titles, comments, subjects, descriptions, homepages, labels, branches, file paths and header or field values. A URL in `--body` or `-c` therefore never picks the account. The cost of an unknown boolean flag is that the positional after it is skipped too and the current directory decides.

### What passes straight through

- A call that already sets `GH_TOKEN` or `GITHUB_TOKEN` (an explicit pin).
- `gh auth`, `config`, `alias`, `extension`, `help`, `version`, `completion`, and bare `gh`.
- `gh gist`: gists always belong to the logged-in user.
- No owner found, an owner not in the map, or an owner mapped to the default account.

### Fails open

Anything unexpected runs the real `gh` unchanged: a missing or malformed map, a failed token fetch, an unparseable call. The wrapper never uses `set -e`, turns off tracing first so a caller's `set -x` can't print the token, and runs on macOS `/bin/bash` 3.2. When looking for the real `gh` it skips every resolver directory on `PATH` and every resolver copy that already ran for this call (tracked in `GH_ACCOUNT_RESOLVER_SEEN`), so two copies can't exec each other in a circle, while `gh` aliases or extensions that call `gh` again still work. Globbing is off, so a `*` in a query can't expand to file names.

### Footprint

Nothing in your shell setup, `~/.config/gh` or global `gh` state changes, and your own terminal is unaffected. `PATH` changes only for this workspace's Claude Bash commands, through Claude Code's own per-session file under `~/.claude/session-env/<session-id>/`. The workspace gains the ignored directory `.claude/gh-account-resolver/`.

### Limits

- `gh` called by absolute path (e.g. `/opt/homebrew/bin/gh`) is not routed.
- Only the owner is matched, not the host: `-R ghe.example.com/work-org/x` gets the github.com token mapped for `work-org`.
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
