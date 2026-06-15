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
| `notes` → `notes/credentials-1password-policy.md` | The full credential-handling mechanics: JIT retrieval, `op://` referencing + syntax limits, the Claude-Code-doesn't-resolve-`op://` gotcha, alternatives, item-creation requests, and 1Password SSH-agent git auth. |

Content-only — no binary. A `cg 1password get|whoami` wrapper over the `op` CLI
is planned for a later release (see [CHANGELOG](CHANGELOG.md)).

## Requirements

The 1Password app and CLI (`op`) installed and signed in. The extension assumes
nothing — verify with `op whoami` before relying on it.

## Authoring / contributing

See the Consigliere [extension authoring guide](https://github.com/mnemcik/consigliere/blob/main/EXTENSIONS.md).
The manifest is `cg-extension.json`; CI validates it against the
[canonical schema](https://github.com/mnemcik/cg-extensions-registry/blob/main/schema/cg-extension.schema.json).

## License

MIT — see [LICENSE](LICENSE).
