# 1password

A [Consigliere](https://github.com/mnemcik/consigliere) extension that makes
**1Password the authoritative credential store** for a workspace.

It teaches Claude to surface 1Password whenever credentials enter a session —
how to retrieve secrets just-in-time with `op`, reference them by `op://` path in
committed code, choose a deliberate alternative when 1Password doesn't fit, and
ask the user to create vault items rather than guessing.

## Install

```sh
cg extension install cg/1password   # fully-qualified: <registry>/<extension>, requires cg v1.6.0+
# or, without the registry (this extension is a subdir of the monorepo):
cg extension install https://github.com/mnemcik/cg-extensions --path 1password
```

Remove cleanly with `cg extension remove 1password`; update with
`cg extension update 1password`.

## What it contributes

| Contribution | What lands |
|--------------|-----------|
| `claude-md-sections` → `credentials-1password` | A pointer-style rule block in your `CLAUDE.md` (under an `ext:1password:section` marker) that triggers the policy whenever a credential appears. |
| `notes` → `notes/credentials-1password-policy.md` | The full credential-handling mechanics: JIT retrieval, `op://` referencing + syntax limits, the Claude-Code-doesn't-resolve-`op://` gotcha, alternatives, item-creation requests, and 1Password SSH-agent git auth, including how to tell "app not running", "locked" and "key in a non-default vault" apart. |
| `hooks` → `PostToolUse` + `PostToolUseFailure` | `.claude/hooks/1password-ssh-auth-hint.sh` and `…-on-failure.sh`: after each Bash command, if the output shows git or ssh failing to authenticate (`Permission denied (publickey)`, `agent refused operation`, `fatal: Authentication failed for`, `fatal: could not read Username for`), add the 1Password remedy to Claude's context. No note has to be loaded for the remedy to arrive. |

No binary. A `cg 1password get|whoami` wrapper over the `op` CLI
is planned for a later release (see [CHANGELOG](CHANGELOG.md)).

### The SSH-auth hint hook

Claude Code passes a hook the command's output: `tool_response` for a command
that exited 0, `error` for one that did not
([hooks reference](https://code.claude.com/docs/en/hooks)). The two events are
separate, so the hook is registered for both, as two identical files: cg
registers each wrapper file under exactly one event.

- **Cheap when nothing matches.** cg registers hooks without a matcher, so the
  hook runs after every tool call. On output without one of the phrases it
  runs a single fixed-string `grep` and exits. It never calls `op` or the
  network.
- **Matches the error, not a mention of it.** It reads only the output, never
  the command, and only lines that start the way ssh and git print them. A
  `grep` hit, a diff line or a document quoting the phrase does not trigger it.
- **Echoes nothing back.** The added text is fixed; nothing from the command
  or its output is repeated.
- **Fails silent.** Without `jq`, on malformed input or for another tool, it
  exits 0 with no output. Runs on macOS `/bin/bash` 3.2, bash 5 and Git Bash on
  Windows; `tests/run.sh` covers all three in CI.

## Requirements

The 1Password app and CLI (`op`) installed and signed in. The extension assumes
nothing — verify with `op whoami` before relying on it.

The hook needs `jq`; without it the hook does nothing and the note still
carries the guidance.

## Authoring / contributing

See the Consigliere [extension authoring guide](https://github.com/mnemcik/consigliere/blob/main/EXTENSIONS.md).
The manifest is `cg-extension.json`; CI validates it against the
[canonical schema](https://github.com/mnemcik/cg-extensions-registry/blob/main/schema/cg-extension.schema.json).

## License

MIT — see [LICENSE](LICENSE).
