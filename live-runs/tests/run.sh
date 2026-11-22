#!/usr/bin/env bash
# Test suite for bin/cg-live and bin/cg-live-tee. Uses a fake claude that
# prints stream-json events and runs Bash tool calls and a hook through
# CLAUDE_CODE_SHELL_PREFIX in the exact shapes Claude Code 2.1.325 sends
# (captured from the real CLI): `<setup> && eval <ARG> < /dev/null && pwd -P >| <file>`,
# ARG a bare word or one single-quoted string with ' written as '"'"'.
# Never calls the real claude or a real tmux.
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
# GNU stat first: BSD stat rejects -c, while GNU stat accepts -f (filesystem info) and would print junk.
mode()     { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

# Fake claude: checks its flags, emits events, runs a tool call and a hook
# through the prefix like Claude Code does, then exits 3.
cat > "$T/claude" <<'C'
#!/usr/bin/env bash
[ "$1 $2 $3 $4" = "-p --output-format stream-json --verbose" ] || { echo "bad flags: $*" >&2; exit 64; }
printf '%s\n' "PASSED: ${*:5}" > "$FAKE_ARGS"
echo '{"type":"system","subtype":"init","model":"m-1","cwd":"/w","session_id":"s-1"}'
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"echo '"'"'it works'"'"'; echo err >&2; exit 4"}}]}}'
out=$("$CLAUDE_CODE_SHELL_PREFIX" "true && eval 'echo '\"'\"'it works'\"'\"'; echo err >&2; exit 4' < /dev/null && pwd -P >| /dev/null" 2>&1); rc=$?
printf '%s\n' "rc=$rc out=$out" > "$FAKE_TOOL"
# A one-word command is sent unquoted; a pipeline stays inside the quotes.
"$CLAUDE_CODE_SHELL_PREFIX" "true && eval pwd < /dev/null && pwd -P >| /dev/null" >/dev/null
"$CLAUDE_CODE_SHELL_PREFIX" "true && eval 'printf \"a\\nb\\n\" | wc -l' < /dev/null && pwd -P >| /dev/null" >/dev/null
# A hook containing "eval '" is not a Bash call: untouched, stderr kept separate.
"$CLAUDE_CODE_SHELL_PREFIX" "echo hook-ran; echo \"eval 'x'\" >/dev/null; echo hook-err >&2" >> "$FAKE_TOOL" 2>"$FAKE_TOOL.hookerr"
# Files the agent creates, directly and through a Bash call, keep the caller's umask.
touch "$FAKE_TOOL.agentfile"
"$CLAUDE_CODE_SHELL_PREFIX" "true && eval 'touch $FAKE_TOOL.toolfile' < /dev/null && pwd -P >| /dev/null" >/dev/null
echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"Exit code 4\nit works\nerr"}]}}'
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"All done."}]}}'
echo 'not json'
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"duration_ms":90000,"total_cost_usd":0.123456,"session_id":"s-1","result":"All done."}'
exit 3
C
chmod +x "$T/claude"
export CG_LIVE_CLAUDE="$T/claude" CG_LIVE_DIR="$T/runs" FAKE_ARGS="$T/args" FAKE_TOOL="$T/tool" CG_LIVE_NO_WATCH=1
export SHELL=/bin/bash CLAUDE_CODE_SHELL=/bin/bash
umask 022

# --- usage ---
expect "no args" 2 "$LIVE"
contains "no args" "$err" "usage: cg live run"
contains "usage lists --until-pane" "$err" "cg live watch [--events | --cmds] [--once] [--until-pane ID] [file]"
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
lacks "hook stderr not merged" "$tool" "hook-err"
contains "hook stderr kept" "$(cat "$T/tool.hookerr")" "hook-err"
log=$(strip < "$cl")
contains "cmd header" "$log" "\$ echo 'it works'; echo err >&2; exit 4"
contains "cmd output" "$log" "it works"
contains "cmd stderr" "$log" "err"
contains "cmd exit" "$log" "exit 4"
lacks "hook not logged" "$log" "hook-ran"
contains "bare word logged" "$log" "\$ pwd"
contains "pipeline logged" "$log" "\$ printf \"a\\nb\\n\" | wc -l"
lacks "no quoting residue" "$log" "/dev/null"

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

# --- the logs are private, but the agent's own files are not ---
[ "$(mode "$T/tool.agentfile")" = 644 ] && ok || bad "agent's file mode $(mode "$T/tool.agentfile"), want 644 (umask leaked into claude)"
[ "$(mode "$T/tool.toolfile")" = 644 ] && ok || bad "tool's file mode $(mode "$T/tool.toolfile"), want 644 (umask leaked into the Bash call)"

# --- a command that literally contains '\'' is logged as written ---
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\"'\"'/g")"; }
lit='printf "%s\n" '"'"'\'"'"''"'"
: > "$T/lit.log"
CG_LIVE_CMD_LOG="$T/lit.log" "$TEE" "true && eval $(shq "$lit") < /dev/null && pwd -P >| /dev/null" >/dev/null 2>&1
contains "literal '\\'' kept" "$(strip < "$T/lit.log")" "\$ $lit"

# --- private logs; no collision between runs in the same second ---
[ "$(mode "$T/runs")" = 700 ] && ok || bad "log dir mode $(mode "$T/runs"), want 700"
[ "$(mode "$(readlink "$ev")")" = 600 ] && ok || bad "events file mode $(mode "$(readlink "$ev")"), want 600"
[ "$(mode "$(readlink "$cl")")" = 600 ] && ok || bad "cmd log mode $(mode "$(readlink "$cl")"), want 600"
"$LIVE" run same -- x >/dev/null 2>&1; "$LIVE" run same -- x >/dev/null 2>&1
[ "$(ls "$T/runs" | grep -c -- '-same.events.jsonl$')" = 2 ] && ok || bad "two same-label runs share a log: $(ls "$T/runs")"

# --- an existing log directory keeps its own mode; the files are still private ---
mkdir -p "$T/shared"; chmod 755 "$T/shared"
expect "existing dir" 3 env CG_LIVE_DIR="$T/shared" "$LIVE" run keep -- x
[ "$(mode "$T/shared")" = 755 ] && ok || bad "existing log dir changed to $(mode "$T/shared"), want it kept at 755"
[ "$(mode "$(readlink "$T/shared/latest.events.jsonl")")" = 600 ] && ok || bad "log file in an existing dir is not 600"

# --- stopping a background viewer kills only the viewer, not its caller ---
o=$(bash -c '"$0" watch "$1" >/dev/null 2>&1 & p=$!; sleep 1; kill -TERM $p; wait $p; echo caller-survived' "$LIVE" "$(readlink "$ev")" 2>&1)
contains "kill scope" "$o" "caller-survived"

# --- fake tmux: records split-window args; a pane "exists" while its flag file does ---
cat > "$T/tmux" <<A
#!/bin/sh
case "\$1" in
  list-panes) [ "\$2" = -a ] && [ -e "$T/pane-alive" ] && echo %5; exit 0 ;;
  split-window) for a in "\$@"; do printf '%s\n' "\$a"; done > "$T/split.args"; echo %9 ;;
  set-option) exit 0 ;;
  display-message) exit 0 ;;  # like real tmux: exits 0 even for a closed pane
esac
A
chmod +x "$T/tmux"
odd="$T/runs dir'q"
expect "split" 3 env -u CG_LIVE_NO_WATCH TMUX=/tmp/s,1,0 TMUX_PANE=%5 CG_LIVE_TMUX="$T/tmux" CG_LIVE_DIR="$odd" "$LIVE" run split -- x
args=$(cat "$T/split.args" 2>/dev/null)
contains "split env arg" "$args" "CG_LIVE_DIR=$odd"
contains "split argv" "$args" "$(printf -- '--\n%s\nwatch\n--until-pane\n%%5' "$(cd "$here/../bin" && pwd)/cg-live")"

# --- --until-pane: the viewer exits when the agent's pane closes ---
touch "$T/pane-alive"
CG_LIVE_TMUX="$T/tmux" "$LIVE" watch --until-pane %5 "$(readlink "$ev")" >/dev/null 2>&1 & wp=$!
sleep 1; kill -0 $wp 2>/dev/null && ok || bad "until-pane: viewer exited while the pane is alive"
rm -f "$T/pane-alive"; sleep 4
if kill -0 $wp 2>/dev/null; then bad "until-pane: viewer still running after the pane closed"; kill $wp; else ok; fi

# --- --until-pane when tmux can't be reached: the viewer says so and stops ---
printf '#!/bin/sh\nexit 1\n' > "$T/tmux-down"; chmod +x "$T/tmux-down"
CG_LIVE_TMUX="$T/tmux-down" "$LIVE" watch --until-pane %5 "$(readlink "$ev")" >/dev/null 2>"$T/down.err" & dp=$!
sleep 2; if kill -0 $dp 2>/dev/null; then bad "unreachable tmux: viewer still running"; kill $dp; else ok; fi
contains "unreachable tmux message" "$(cat "$T/down.err")" "tmux is not reachable"

# --- viewer hint outside tmux ---
expect "hint" 3 env -u CG_LIVE_NO_WATCH -u TMUX "$LIVE" run hint -- x
contains "hint" "$err" "watch with: cg live watch"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
