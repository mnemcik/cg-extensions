# gh-account-resolver

A Consigliere extension that auto-selects the correct logged-in `gh` account **per command**, so concurrent Claude Code sessions don't fight over the globally-active `gh` account.

## Problem

`gh auth switch` writes shared state to `~/.config/gh/hosts.yml`. When several sessions run in parallel, that state drifts and commands hit the wrong account → spurious `404 / Repository not found`.

## Mechanism

A `PreToolUse` hook inspects each Bash command. When it runs `gh` against a repo whose **owner** maps to a non-default account (per `.claude/gh-account-map`), it prefixes the command with `GH_TOKEN="$(gh auth token --user <account>)"`. The literal token is never written — it's resolved live from the keyring at execution time.

- **Fails open:** any error, unparseable input, missing `gh`, or unmapped owner → the original command runs unchanged.
- **Zero global footprint:** no `~/.zshrc`, `~/.config`, PATH, or global `gh`-state changes.
- Owner is resolved from an explicit `--repo`/`-R` flag, else from the working directory's `origin` remote.

## Install

```
cg extension install cg/gh-account-resolver      # once published to the registry
cg extension install <path-or-git-url>           # local / direct
```

## Configure

Create `.claude/gh-account-map` (workspace-local user config; not shipped by this extension):

```
default = mnemcik
idellabv     = mnemcik-work
Visma-Idella = mnemcik-work
```

One `owner = account` per line. `default` names the globally-active account that needs no rewrite. Owner match is case-insensitive; `#` starts a comment. Add a line to route a new org — no code change.

## Contributes

- A `PreToolUse` hook (`hooks/resolve.sh`).
- A CLAUDE.md section documenting the routing behaviour and map format.
