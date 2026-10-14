---
title: "Credentials & Secrets — 1Password in the Loop"
category: process
tags: [credentials, 1password, security, ai-instructions]
---

# Credentials & Secrets — 1Password in the Loop

> Shipped by the [`1password`](https://github.com/mnemcik/cg-extensions/tree/main/1password) Consigliere extension. Edit the source there, not this copy — `cg extension update 1password` overwrites it.

## When to load this note

Any session that designs for, reviews, or touches a credential — API tokens, session cookies, webhook secrets, service accounts, DB passwords, signing keys — plus any security analysis or threat model involving credential handling, and any git fetch/push/clone that fails with an SSH authentication error (`Permission denied (publickey)`).

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
- **Failure mode:** a `fetch`/`push`/`clone` that fails with `Permission denied (publickey)` means the 1Password agent offered no usable key. ssh does not say why. There are three causes, and a probe of the agent socket tells them apart.
- **Probe the agent socket directly** (it lists public keys only, never private material). Query the 1Password socket explicitly rather than whatever `SSH_AUTH_SOCK` happens to be set to:
  - macOS: `SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" ssh-add -l`
  - Linux: `SSH_AUTH_SOCK="$HOME/.1password/agent.sock" ssh-add -l`
  - Windows: `ssh-add -l` (1Password listens on the `\\.\pipe\openssh-ssh-agent` named pipe; there is no socket to set)
- **Read the probe result:**

  | Probe says | Cause | Remedy |
  |---|---|---|
  | `Connection refused`, `No such file or directory`, or `Error connecting to agent` | **1Password is not running** (the app was quit, so nothing is serving the socket) | Ask the user to start 1Password. To keep the agent alive when the window closes, enable "Keep 1Password in the menu bar" (macOS), "…in the notification area" (Windows) or "…in the system tray" (Linux). |
  | `The agent has no identities` | Usually **1Password is locked**, or Settings → Developer → "Use the SSH agent" is off: the agent answers but serves no keys | Ask the user to unlock 1Password (and enable the SSH agent setting if it is off). A locked 1Password can also show an unlock prompt on the user's screen; if nobody answers, ssh fails with `agent refused operation`. |
  | Keys are listed, but the host still refuses | **The key this host needs is in a non-default vault.** Without a config file the agent serves only SSH keys in the default Personal, Private or Employee vault | Ask the user to add the vault to `~/.config/1Password/ssh/agent.toml` (Windows: `%LOCALAPPDATA%\1Password\config\ssh\agent.toml`) as `[[ssh-keys]]` / `vault = "<name>"`. If the file is new, lock and unlock 1Password once so it is picked up. Don't edit their config yourself. If the key is in a served vault, it is not registered on the host account. |

- **Remedy: get the agent serving the key, then retry the same command.** Do **not** route around it — no switching the remote to HTTPS, no on-disk key, no skipping/deferring the push, and do **not** branch off stale local state to dodge a failing fetch. The only correct fix is getting the 1Password agent available.
- **Verify end to end:** `ssh -T git@<host>` should print a successful-authentication greeting.
- **This extension also ships a hook.** After every Bash command, `.claude/hooks/1password-ssh-auth-hint.sh` (and its `-on-failure` twin for commands that exit non-zero) looks for git or ssh authentication errors in the output (`Permission denied (publickey)`, `agent refused operation`, `fatal: Authentication failed for`, `fatal: could not read Username for`) and adds the remedy above to Claude's context. The guidance therefore arrives even when this note was not loaded.

Sources: [1Password SSH agent](https://www.1password.dev/ssh/agent/), [Get started](https://www.1password.dev/ssh/get-started/) (socket paths, keeping the app running, unlock prompt), [agent config file](https://www.1password.dev/ssh/agent/config/) (default vaults, `agent.toml`).
