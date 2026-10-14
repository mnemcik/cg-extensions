#!/usr/bin/env bash
# 1password ssh-auth-hint: when a Bash command's output shows git or ssh failing
# to authenticate, tell Claude what to check in 1Password, so the
# 1Password-specific remedy no longer depends on Claude choosing to load the
# credentials note.
#
# Registered twice, so it is shipped as two identical files (tests/run.sh
# checks that they are byte-identical):
#   hooks/ssh-auth-hint.sh             PostToolUse         (the command exited 0,
#                                        e.g. `git fetch 2>&1 | tail`)
#   hooks/ssh-auth-hint-on-failure.sh  PostToolUseFailure  (the command exited
#                                        non-zero)
# cg registers each wrapper under exactly one event and drops any earlier
# registration of the same file, so one file cannot serve both events.
#
# Input (https://code.claude.com/docs/en/hooks): JSON on stdin. PostToolUse
# carries the result in `tool_response` (for Bash: `stdout`, `stderr`);
# PostToolUseFailure carries it in `error` ("Exit code N" then the output).
# cg registers hooks with an empty matcher, so this runs after every tool
# call and filters on `tool_name` itself.
#
# Output: on a match, a JSON `hookSpecificOutput.additionalContext`, which
# Claude Code adds next to the tool result. The text is fixed. Nothing from
# the command or its output is echoed back.
#
# Cost and failure: one grep over the input on the non-match path, nothing
# else (no `op`, no network). Anything unexpected (no jq, malformed JSON,
# another tool) exits 0 silently. Portable to macOS /bin/bash 3.2 and Git
# Bash on Windows: no associative arrays, no ${var,,}, no GNU-only flags.

set +e +u +x +v 2>/dev/null

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

# Cheap prefilter on the raw JSON: none of these phrases contain characters
# JSON escapes, so a fixed-string grep finds them before anything is parsed.
printf '%s' "$input" | grep -qF \
	-e 'Permission denied (publickey' \
	-e 'agent refused operation' \
	-e 'fatal: Authentication failed for' \
	-e 'fatal: could not read Username for' 2>/dev/null || exit 0

command -v jq >/dev/null 2>&1 || exit 0

# The output only, never `tool_input`: a command that merely mentions the
# phrase (grep, a commit message) must not trigger the hint.
out=$(printf '%s' "$input" | jq -r '
	select(.tool_name == "Bash")
	| [ (.tool_response | if type == "object" then (.stdout, .stderr)
	                      elif type == "string" then . else empty end),
	    .error ]
	| map(strings) | join("\n")' 2>/dev/null) || exit 0
[ -n "$out" ] || exit 0
event=$(printf '%s' "$input" | jq -r '.hook_event_name // "PostToolUse"' 2>/dev/null | tr -d '\r') || exit 0
case "$event" in PostToolUse | PostToolUseFailure) ;; *) exit 0 ;; esac

# Anchored to the start of a line, as ssh and git print them. Quoted file
# content (grep hits, diffs, cat of a doc) starts its lines with something
# else, so it does not match. `tr` removes Windows CRs before matching.
lines=$(printf '%s\n' "$out" | tr -d '\r')
kind=""
if printf '%s\n' "$lines" | grep -qE \
	-e '^[A-Za-z0-9._-]+@[^ ]+: Permission denied \(publickey' \
	-e '^sign_and_send_pubkey: signing failed .*agent refused operation' 2>/dev/null; then
	kind=ssh
elif printf '%s\n' "$lines" | grep -qE \
	-e "^fatal: Authentication failed for '" \
	-e "^fatal: could not read Username for '" 2>/dev/null; then
	kind=https
fi
[ -n "$kind" ] || exit 0

# `read -d ''` rather than $(cat <<EOF): bash 3.2 mis-parses quotes in a
# here-document inside $(...). read returns 1 at end of input; that is fine.
msg=""
if [ "$kind" = ssh ]; then
	IFS= read -r -d '' msg <<'EOF'
1password extension: this is an SSH authentication failure. With the 1Password SSH agent the cause is almost always the agent, not the key, the remote or the network. Do not route around it: no switching the remote to HTTPS, no on-disk key, no skipping or deferring the push, no working from stale local state.

Probe the agent socket directly (it lists public keys only):
  macOS:   SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" ssh-add -l
  Linux:   SSH_AUTH_SOCK="$HOME/.1password/agent.sock" ssh-add -l
  Windows: ssh-add -l   (1Password listens on \\.\pipe\openssh-ssh-agent)

Read the result:
- "Connection refused", "No such file or directory" or "Error connecting to agent": the 1Password app is not running. Ask the user to start it (and to keep it in the menu bar or tray, so closing the window does not stop the agent).
- "The agent has no identities": the agent is up but serving no keys. Usually 1Password is locked, or Settings > Developer > "Use the SSH agent" is off. Ask the user to unlock it. A locked 1Password can also show an unlock prompt on the user's screen; if nobody answers it, ssh fails with "agent refused operation".
- Keys are listed but this host still refuses: the key this host needs is not among them. It is probably in a vault other than the default Personal, Private or Employee vault, so the agent does not serve it until the vault is listed in agent.toml ([[ssh-keys]] vault = "<name>"; ~/.config/1Password/ssh/agent.toml, on Windows %LOCALAPPDATA%\1Password\config\ssh\agent.toml), (if the file is new, lock and unlock 1Password once so it is picked up). Ask the user; do not edit their config.

Then re-run the same command. Full rules: notes/credentials-1password-policy.md.
EOF
else
	IFS= read -r -d '' msg <<'EOF'
1password extension: git could not authenticate over HTTPS (no credential was available, or it was rejected). If this workspace uses the 1Password SSH agent for git, check `git remote -v`: an https:// remote where an SSH one is expected is the cause. Ask the user before changing it.

If HTTPS is intended, the credential belongs in 1Password. Ask the user which item holds it, and fetch it just-in-time with `op`. Never write a token into the remote URL, git config, a credential file or shell history. Full rules: notes/credentials-1password-policy.md.
EOF
fi

jq -nc --arg e "$event" --arg m "$msg" \
	'{hookSpecificOutput: {hookEventName: $e, additionalContext: $m}}' 2>/dev/null
exit 0
