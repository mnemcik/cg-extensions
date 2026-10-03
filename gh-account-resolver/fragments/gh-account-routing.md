## GitHub Account Routing (per call)

A `SessionStart` hook (`.claude/hooks/gh-account-resolver-resolve.sh`) puts a `gh` wrapper first on `PATH` for each Claude session in this workspace, so every `gh` call runs under the right logged-in account. This avoids fighting over the globally active account, which `gh auth switch` writes to shared `~/.config/gh/hosts.yml` and which drifts between parallel sessions, causing spurious "Could not resolve to a Repository" errors.

On each call the wrapper finds the repo owner from the call's own arguments: `-R`/`--repo`, `GH_REPO`, a `gh repo` argument, a GitHub URL argument, a `gh api` endpoint or search qualifier, and finally the current directory's git remote. It then runs the real `gh` with `GH_TOKEN` taken live from `gh auth token --user <account>`. The token never appears in a command or in the transcript. Chains, `cd`, variables, loops, `xargs` and `bash -c` all route per call. It **fails open**: an unknown owner or any error runs the real `gh` unchanged. A call that sets `GH_TOKEN` itself, and `gh auth …`, pass straight through.

**Not routed:** `gh` called by absolute path, and `gh` inside other hooks. Sessions started before the extension was installed or upgraded need a restart.

**Configuration:** create `.claude/gh-account-map` with one `owner = account` per line. The `default` key names the globally active account, which needs no routing. Example:

```
default = mnemcik
idellabv     = mnemcik-work
Visma-Idella = mnemcik-work
```

Owner match is case-insensitive; `#` starts a comment. To route a new org to a different account, add one line; no code change. The map is workspace-local user config (not shipped by this extension).
