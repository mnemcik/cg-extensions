## GitHub Account Routing (per-command)

A `PreToolUse` hook (`.claude/hooks/gh-account-resolver.sh`) auto-selects the correct logged-in `gh` account **per command**, so concurrent Claude sessions don't fight over the globally-active `gh` account (which `gh auth switch` writes to shared `~/.config/gh/hosts.yml` and drifts between parallel sessions, causing spurious "404 / Repository not found").

When a Bash command runs `gh` against a repo whose **owner** maps to a non-default account, the hook prefixes the command with `GH_TOKEN="$(gh auth token --user <account>)"` — the literal token is never written, only resolved live from the keyring at execution time. It **fails open**: any error, unparseable input, missing `gh`, or unmapped owner → the original command runs unchanged.

**Configuration:** create `.claude/gh-account-map` with one `owner = account` per line. The `default` key names the globally-active account that needs no rewrite. Example:

```
default = mnemcik
idellabv     = mnemcik-work
Visma-Idella = mnemcik-work
```

Owner match is case-insensitive; `#` starts a comment. To route a new org to a different account, add one line — no code change. The map is workspace-local user config (not shipped by this extension).
