# Credentials & Secrets — 1Password in the Loop

> Shipped by the [`1password`](https://github.com/mnemcik/cg-extensions/tree/main/1password) Consigliere extension. Edit the source there, not this copy — `cg extension update 1password` overwrites it.

## When to load this note

Any session that designs for, reviews, or touches a credential — API tokens, session cookies, webhook secrets, service accounts, DB passwords, signing keys — plus any security analysis or threat model involving credential handling.

The one-line rule in `CLAUDE.md` ensures Claude surfaces 1Password whenever credentials appear; this note carries the full mechanics for retrieval, referencing, and escalation.

## Context

**1Password is the authoritative credential store for this workspace.** This extension assumes the 1Password app and CLI (`op`) are installed and signed in, and that 1Password is the preferred tool for API tokens, session cookies, service credentials, and any other secret material. Verify `op` is configured (`op whoami`) before relying on it — do not assume.

## Rules

1. **Always surface 1Password when credentials enter the conversation** — as the chosen store or as an explicit "considered and rejected because X". Never silently skip it.
2. **Retrieve secrets just-in-time via `op`.** Prefer `op run --env-file=...` to scope secrets to a single invocation; `op read "op://<vault>/<item>/<field>"` for one-off reads. Never cache retrieved secrets to disk, env files, or shell history.
3. **Reference secrets by `op://` path in committed code.** Templates and `.env.template` files may contain `op://` references; they must never contain the literal secret. Gitignore any `.secrets/` or similar working directories.
4. **If 1Password doesn't fit**, name the chosen alternative (OS keychain, hardware key, platform-managed secret) and the reason. Do not silently drop to a weaker option like a plaintext file or an env var with a real value.
5. **Ask the user to create the 1Password item** — suggest the vault, item name, and field schema explicitly (e.g., "Private vault → '<Service> Session' → concealed fields `token`, `cookie`") rather than guessing.

## `op://` reference syntax

`op://` paths are parsed strictly: vault / item / field segments accept alphanumerics plus `-` and `_` only. Characters like `(`, `)`, and `%` are rejected by the parser — rename items or use the item's UUID instead of a display name containing them.

## Claude Code does not natively resolve `op://`

Claude Code does **not** expand `op://` references inside `settings.json` or MCP `env` blocks — they are passed through literally. To inject a real secret, wrap the launch in `op run --env-file=...` (or `op read` at startup) so `op` resolves the reference before the process sees the environment; don't expect the harness to do it.

## Git / SSH authentication via the 1Password agent

If you authenticate git over SSH using 1Password's SSH agent, the private keys live in 1Password, not on disk; `~/.ssh/*.pub` are only public references the config uses to select which agent identity to offer.

- **If your `~/.ssh/config` already routes hosts through the 1Password agent socket, do not rewrite it.** The documented pattern points `IdentityAgent` (or `IdentityFile` at the matching `.pub`) at the 1Password agent socket. Do **not** "fix" it to use on-disk private keys or a different agent.
- **Failure mode:** a `fetch`/`push` that fails with `Permission denied (publickey)` (or `ssh-add -l` reporting "agent has no identities") means **1Password is locked or its SSH agent is unavailable** — ssh then falls back to an empty agent and has no key to offer.
- **Remedy: unlock 1Password and retry.** Ensure 1Password is unlocked and Settings → Developer → "Use the SSH agent" is enabled, then re-run the git operation. Do **not** route around it — no switching the remote to HTTPS, no on-disk key, no skipping/deferring the push, and do **not** branch off stale local state to dodge a failing fetch. The only correct fix is getting the 1Password agent available.
- **Verify the agent is serving keys:** `ssh -T git@<host>` should print a successful-authentication greeting; or query the socket directly with `ssh-add -l` against the 1Password agent socket (expect your configured key).
