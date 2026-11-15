#!/usr/bin/env bash
# Test suite for bin/cg-live and bin/cg-live-tee. Uses a fake claude that
# prints stream-json events and runs one Bash tool call and one hook through
# CLAUDE_CODE_SHELL_PREFIX the way Claude Code does. Never calls the real claude.
#
#   tests/run.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
LIVE="$here/../bin/cg-live"
TEE="$here/../bin/cg-live-tee"

T=$(mktemp -d "${TMPDIR:-/tmp}/cg-live-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$*" >&2; }
expect() {
  local name=$1 want=$2; shift 2
  out=$("$@" 2>"$T/stderr"); local got=$?
  err=$(cat "$T/stderr")
  if [ "$got" -eq "$want" ]; then ok; else bad "$name: exit $got, want $want; stdout: $out; stderr: $err"; fi
}
contains() { case "$2" in *"$3"*) ok ;; *) bad "$1: lacks '$3' in: $2" ;; esac; }
lacks()    { case "$2" in *"$3"*) bad "$1: has '$3' in: $2" ;; *) ok ;; esac; }
strip()    { sed 's/\x1b\[[0-9;]*m//g'; }

# Fake claude: checks its flags, emits events, runs a tool call and a hook
# through the prefix like Claude Code does, then exits 3.
cat > "$T/claude" <<'C'
#!/usr/bin/env bash
[ "$1 $2 $3 $4" = "-p --output-format stream-json --verbose" ] || { echo "bad flags: $*" >&2; exit 64; }
printf '%s\n' "PASSED: ${*:5}" > "$FAKE_ARGS"
echo '{"type":"system","subtype":"init","model":"m-1","cwd":"/w","session_id":"s-1"}'
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"echo '"'"'it works'"'"'; echo err >&2; exit 4"}}]}}'
out=$("$CLAUDE_CODE_SHELL_PREFIX" "true && eval 'echo '\''it works'\''; echo err >&2; exit 4' < /dev/null && pwd -P >| /dev/null" 2>&1); rc=$?
printf '%s\n' "rc=$rc out=$out" > "$FAKE_TOOL"
"$CLAUDE_CODE_SHELL_PREFIX" "echo hook-ran" >> "$FAKE_TOOL"
echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"Exit code 4\nit works\nerr"}]}}'
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"All done."}]}}'
echo 'not json'
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"duration_ms":90000,"total_cost_usd":0.123456,"session_id":"s-1","result":"All done."}'
exit 3
C
chmod +x "$T/claude"
export CG_LIVE_CLAUDE="$T/claude" CG_LIVE_DIR="$T/runs" FAKE_ARGS="$T/args" FAKE_TOOL="$T/tool" CG_LIVE_NO_WATCH=1
export SHELL=/bin/bash CLAUDE_CODE_SHELL=/bin/bash

# --- usage ---
expect "no args" 2 "$LIVE"
contains "no args" "$err" "usage: cg live run"
expect "run without claude args" 2 "$LIVE" run only-label

# --- run: result JSON on stdout, claude's exit code, args passed through ---
expect "run" 3 "$LIVE" run "my label/1" --model x -- '/speckit-plan go'
[ "$(printf '%s' "$out" | jq -r .type)" = result ] && ok || bad "run stdout is not the result event: $out"
[ "$(printf '%s' "$out" | jq -r 'has("_ts")')" = false ] && ok || bad "run stdout keeps _ts: $out"
[ "$(printf '%s' "$out" | jq -r .session_id)" = s-1 ] && ok || bad "run stdout session_id: $out"
contains "args" "$(cat "$T/args")" "PASSED: --model x -- /speckit-plan go"
contains "run label" "$err" "my-label-1"
ev="$T/runs/latest.events.jsonl"; cl="$T/runs/latest.cmd.log"
[ -L "$ev" ] && [ -L "$cl" ] && ok || bad "latest symlinks missing"
[ "$(jq -s 'map(has("_ts")) | all' "$ev")" = true ] && ok || bad "events lack _ts"
[ "$(jq -s 'map(select(.type=="raw")) | length' "$ev")" = 1 ] && ok || bad "non-JSON line not kept as raw"

# --- tee: the tool call gets its output and exit code; the log gets them live ---
tool=$(cat "$T/tool")
contains "tee result" "$tool" "rc=4"
contains "tee stdout" "$tool" "it works"
contains "tee stderr" "$tool" "err"
contains "hook untouched" "$tool" "hook-ran"
log=$(strip < "$cl")
contains "cmd header" "$log" "\$ echo 'it works'; echo err >&2; exit 4"
contains "cmd output" "$log" "it works"
contains "cmd stderr" "$log" "err"
contains "cmd exit" "$log" "exit 4"
lacks "hook not logged" "$log" "hook-ran"

# --- tee without a log: pass-through only ---
o=$(env -u CG_LIVE_CMD_LOG "$TEE" "eval 'echo plain; exit 5' < /dev/null" 2>&1); rc=$?
[ "$rc" -eq 5 ] && ok || bad "tee without log: rc $rc"
contains "tee without log" "$o" "plain"

# --- watch --once: renders the run ---
expect "watch once" 0 "$LIVE" watch --once
view=$(printf '%s' "$out" | strip)
contains "watch init" "$view" "▶ run started  model m-1  cwd /w"
contains "watch tool" "$view" "⚙ Bash  echo 'it works'; echo err >&2; exit 4"
contains "watch error result" "$view" "✗ Bash"
contains "watch text" "$view" "● All done."
contains "watch raw" "$view" "not json"
contains "watch finished" "$view" "■ run finished: success  turns 2  1.5 min  \$0.12"
contains "watch cmd output" "$view" "   │ it works"
expect "watch events only" 0 "$LIVE" watch --events --once "$(readlink "$ev")"
lacks "events only" "$(printf '%s' "$out" | strip)" "│ it works"
expect "watch cmds only" 0 "$LIVE" watch --cmds --once
contains "cmds only" "$(printf '%s' "$out" | strip)" "exit 4"

# --- viewer hint outside tmux ---
expect "hint" 3 env -u CG_LIVE_NO_WATCH -u TMUX "$LIVE" run hint -- x
contains "hint" "$err" "watch with: cg live watch"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
