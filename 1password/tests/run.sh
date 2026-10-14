#!/usr/bin/env bash
# Test suite for hooks/ssh-auth-hint.sh, fed fixture hook payloads. Never
# calls `op`, ssh or the network.
#
#   tests/run.sh              run every case under `bash` (and /bin/bash too
#                             when it is a different binary, e.g. macOS 3.2)
#   tests/run.sh BASH...      run under the named bash binaries only
#
# Payload shapes follow https://code.claude.com/docs/en/hooks: PostToolUse
# carries `tool_response` (Bash: stdout, stderr, interrupted, isImage);
# PostToolUseFailure carries `error` ("Exit code N" then the output).

set -u
here=$(cd "$(dirname "$0")" && pwd)
hook="$here/../hooks/ssh-auth-hint.sh"
hook2="$here/../hooks/ssh-auth-hint-on-failure.sh"

shells=("$@")
if [ ${#shells[@]} -eq 0 ]; then
	shells=(bash)
	if [ -x /bin/bash ] && [ "$(command -v bash)" != /bin/bash ]; then shells+=(/bin/bash); fi
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/op-hint-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

pass=0
fail=0
ok() { # ok NAME CMD...
	if "${@:2}"; then pass=$((pass + 1)); else
		fail=$((fail + 1))
		printf 'FAIL [%s] %s\n' "$SH" "$1"
	fi
}

# json STRING: a JSON string literal (jq does the escaping; stdin, not
# --arg, so a multi-megabyte string does not hit the argument-size limit).
json() { printf '%s' "$1" | jq -Rs .; }

# post STDOUT STDERR [TOOL] [COMMAND]: a PostToolUse payload.
post() {
	printf '{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"command":%s},"tool_response":{"stdout":%s,"stderr":%s,"interrupted":false,"isImage":false},"tool_use_id":"t"}' \
		"${3:-Bash}" "$(json "${4:-git fetch}")" "$(json "$1")" "$(json "$2")"
}

# failure ERROR [COMMAND]: a PostToolUseFailure payload.
failure() {
	printf '{"session_id":"s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":%s},"tool_use_id":"t","error":%s,"is_interrupt":false}' \
		"$(json "${2:-git fetch}")" "$(json "$1")"
}

# run PAYLOAD: run the hook; stdout in $out, exit code in $rc.
run() {
	out=$(printf '%s' "$1" | "$SH" "$hook" 2>"$T/stderr")
	rc=$?
}

silent() { [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -s "$T/stderr" ]; }
hint() { # hint KIND EVENT
	[ "$rc" -eq 0 ] || return 1
	[ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" = "$2" ] || return 1
	ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext') || return 1
	case "$1" in
	ssh) case "$ctx" in *"ssh-add -l"*"has no identities"*"agent.toml"*) ;; *) return 1 ;; esac ;;
	https) case "$ctx" in *"over HTTPS"*"git remote -v"*) ;; *) return 1 ;; esac ;;
	esac
}

SSH_ERR='git@github.com: Permission denied (publickey).
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.'

for SH in "${shells[@]}"; do
	sh_abs=$(command -v "$SH") || { echo "no such shell: $SH" >&2; exit 2; }
	SH=$sh_abs
	# --- matches
	run "$(failure "Exit code 128
$SSH_ERR")"
	ok "failure event: publickey" hint ssh PostToolUseFailure

	run "$(post "" "$SSH_ERR")"
	ok "success event: publickey on stderr" hint ssh PostToolUse

	run "$(post "Fetching origin
$SSH_ERR" "")"
	ok "success event: 2>&1 merged into stdout" hint ssh PostToolUse

	run "$(failure "Exit code 255
git@github.com: Permission denied (publickey,keyboard-interactive).")"
	ok "publickey among other methods" hint ssh PostToolUseFailure

	run "$(failure 'Exit code 128
sign_and_send_pubkey: signing failed for ED25519 "github" from agent: agent refused operation
git@github.com: Permission denied (publickey).')"
	ok "agent refused operation" hint ssh PostToolUseFailure

	run "$(failure "Exit code 128
fatal: could not read Username for 'https://github.com': terminal prompts disabled")"
	ok "https: could not read Username" hint https PostToolUseFailure

	run "$(failure "Exit code 128
remote: Invalid username or token.
fatal: Authentication failed for 'https://github.com/o/r.git/'")"
	ok "https: Authentication failed" hint https PostToolUseFailure

	crlf=$(printf 'Exit code 128\r\ngit@github.com: Permission denied (publickey).\r\n')
	run "$(failure "$crlf")"
	ok "CRLF output (Windows)" hint ssh PostToolUseFailure

	run "$(post '' '' Bash '' | jq -c '.tool_response = "git@github.com: Permission denied (publickey)."')"
	ok "tool_response as a plain string" hint ssh PostToolUse

	# --- no secrets or output echoed back
	run "$(failure "Exit code 128
token=s3cr3t-value-123
$SSH_ERR")"
	ok "output not echoed back" eval 'case "$out" in *s3cr3t*|*"Could not read from remote"*) false ;; *) true ;; esac'

	# --- non-matches
	run "$(post "Already up to date." "")"
	ok "clean output: silent" silent

	run "$(failure "Exit code 1
bash: ./deploy.sh: Permission denied")"
	ok "unrelated Permission denied: silent" silent

	run "$(failure "Exit code 255
user@host: Permission denied (password).")"
	ok "password auth denied: silent" silent

	run "$(failure "Exit code 1
psql: error: FATAL:  password authentication failed for user \"app\"")"
	ok "database authentication failed: silent" silent

	run "$(post "notes/x.md:- a fetch that fails with \`Permission denied (publickey)\` means
notes/x.md:git@github.com: Permission denied (publickey)." "" Bash "grep -rn 'Permission denied (publickey)' notes")"
	ok "grep hit quoting the phrase: silent" silent

	run "$(post "+git@github.com: Permission denied (publickey).
-fatal: Authentication failed for 'https://x'" "" Bash "git show HEAD")"
	ok "diff lines quoting the phrase: silent" silent

	run "$(post "ok" "" Bash "echo 'Permission denied (publickey)' >/dev/null")"
	ok "phrase only in the command: silent" silent

	run "$(post "$SSH_ERR" "" Read)"
	ok "non-Bash tool: silent" silent

	run '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_response":{"stdout":"git@github.com: Permission denied (publickey).'
	ok "malformed JSON: silent" silent

	run ""
	ok "empty input: silent" silent

	run "$(failure "Exit code 128
$SSH_ERR" | jq -c '.hook_event_name = "PreToolUse"')"
	ok "other event name: silent" silent

	# --- missing jq: a PATH with the tools the hook needs, minus jq
	mkdir -p "$T/nojq"
	for t in cat grep tr env; do
		p=$(command -v "$t") && ln -sf "$p" "$T/nojq/$t"
	done
	payload=$(failure "Exit code 128
$SSH_ERR")
	# Only meaningful if the prefilter's grep still works on that PATH (a
	# copied Git Bash grep.exe can lose its DLLs, which would make the case
	# pass for the wrong reason).
	if PATH="$T/nojq" "$SH" -c 'printf x | grep -q x' 2>/dev/null; then
		out=$(printf '%s' "$payload" | PATH="$T/nojq" "$SH" "$hook" 2>"$T/stderr")
		rc=$?
		ok "no jq: silent" silent
	else
		echo "SKIP [$SH] no jq: grep does not run from a PATH without jq here"
	fi

	# --- huge output: the non-match path stays cheap, a match at the end is found
	big="$T/big.txt"
	if [ ! -s "$big" ]; then
		i=0
		while [ $i -lt 200 ]; do
			printf 'remote: Counting objects: %d%% (lots of ordinary progress text, padding padding padding)\n' $i
			i=$((i + 1))
		done >"$T/chunk"
		: >"$big"
		i=0
		while [ $i -lt 150 ]; do cat "$T/chunk" >>"$big"; i=$((i + 1)); done # ~3 MB
	fi
	run "$(post "$(cat "$big")" "")"
	ok "huge non-matching output: silent" silent
	start=$(date +%s)
	run "$(post "$(cat "$big")
$SSH_ERR" "")"
	end=$(date +%s)
	ok "huge output, match at the end" hint ssh PostToolUse
	ok "huge output under 5 s" [ $((end - start)) -lt 5 ]
done

# --- the two registered wrappers must stay identical
SH=files
ok "wrappers are byte-identical" cmp -s "$hook" "$hook2"
ok "wrapper is executable" [ -x "$hook" ]
ok "failure wrapper is executable" [ -x "$hook2" ]

echo "passed: $pass  failed: $fail  (shells: ${shells[*]})"
[ "$fail" -eq 0 ]
