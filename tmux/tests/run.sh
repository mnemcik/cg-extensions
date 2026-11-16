#!/usr/bin/env bash
# Test suite for bin/cg-tmux. Uses a fake tmux that records its arguments;
# never starts a real tmux server.
#
#   tests/run.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
LAUNCH="$here/../bin/cg-tmux"
CONF="$(cd "$here/.." && pwd)/tmux.conf"

T=$(mktemp -d "${TMPDIR:-/tmp}/cg-tmux-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$*" >&2; }
expect() {
  local name=$1 want=$2; shift 2
  out=$("$@" 2>&1); local got=$?
  if [ "$got" -eq "$want" ]; then ok; else bad "$name: exit $got, want $want; output: $out"; fi
}
contains() { case "$out" in *"$2"*) ok ;; *) bad "$1: output lacks '$2'; output: $out" ;; esac; }
lacks()    { case "$out" in *"$2"*) bad "$1: output has '$2'; output: $out" ;; *) ok ;; esac; }

# The "agent": prints its arguments one per line, exits 7.
cat > "$T/agent" <<'A'
#!/bin/sh
for a in "$@"; do printf 'ARG[%s]\n' "$a"; done
exit 7
A
# The fake tmux: records its arguments one per line, exits 0.
cat > "$T/tmux" <<A
#!/bin/sh
for a in "\$@"; do printf '%s\n' "\$a"; done > "$T/tmux.args"
exit 0
A
chmod +x "$T/agent" "$T/tmux"
mkdir -p "$T/my.work:space"

# --- usage ---
expect "no args" 2 "$LAUNCH"
contains "no args" "usage: cg-tmux launch --"
expect "no --" 2 "$LAUNCH" launch "$T/agent"
expect "no agent" 2 "$LAUNCH" launch --

# --- inside tmux: the agent runs directly, with its args and exit code ---
expect "inside tmux" 7 env TMUX=/tmp/x,1,0 CG_TMUX_BIN="$T/tmux" "$LAUNCH" launch -- "$T/agent" "a b" ""
contains "inside tmux" "ARG[a b]"
contains "inside tmux" "ARG[]"
[ ! -e "$T/tmux.args" ] && ok || bad "inside tmux: tmux must not be called"

# --- no tmux: warning, then the agent directly ---
expect "no tmux" 7 env -u TMUX CG_TMUX_ASSUME_TTY=1 CG_TMUX_BIN="$T/no-such-tmux" "$LAUNCH" launch -- "$T/agent" x
contains "no tmux" "tmux not found"
contains "no tmux" "ARG[x]"

# --- tmux present: new session with the bundled config, cwd and the agent ---
( cd "$T/my.work:space" && env -u TMUX CG_TMUX_ASSUME_TTY=1 CG_TMUX_BIN="$T/tmux" "$LAUNCH" launch -- "$T/agent" --resume "a b" )
got=$?
[ "$got" -eq 0 ] && ok || bad "tmux present: exit $got"
args=$(cat "$T/tmux.args" 2>/dev/null)
want_prefix=$(printf '%s\n' -L cg -f "$CONF" new-session -s)
case "$args" in "$want_prefix"*) ok ;; *) bad "tmux present: args start wrong (want the dedicated -L cg server): $args" ;; esac
name=$(sed -n 7p "$T/tmux.args")
case "$name" in agent-my-work-space-[0-9][0-9][0-9][0-9][0-9][0-9]-[0-9]*) ok ;; *) bad "session name '$name': want agent-my-work-space-HHMMSS-PID (no . or :)" ;; esac
tail_want=$(printf '%s\n' -c "$(cd "$T/my.work:space" && pwd)" -- "$T/agent" --resume "a b")
[ "$(sed -n '8,$p' "$T/tmux.args")" = "$tail_want" ] && ok || bad "tmux present: tail args: $(sed -n '8,$p' "$T/tmux.args")"

# --- two launches in the same second get different session names ---
n1=$( (env -u TMUX CG_TMUX_ASSUME_TTY=1 CG_TMUX_BIN="$T/tmux" "$LAUNCH" launch -- "$T/agent" >/dev/null; sed -n 7p "$T/tmux.args") )
n2=$( (env -u TMUX CG_TMUX_ASSUME_TTY=1 CG_TMUX_BIN="$T/tmux" "$LAUNCH" launch -- "$T/agent" >/dev/null; sed -n 7p "$T/tmux.args") )
[ "$n1" != "$n2" ] && ok || bad "same-second launches share the session name $n1"

# --- no terminal: the agent runs directly (tmux could not attach) ---
rm -f "$T/tmux.args"
expect "no tty" 7 env -u TMUX -u CG_TMUX_ASSUME_TTY CG_TMUX_BIN="$T/tmux" "$LAUNCH" launch -- "$T/agent" z </dev/null
contains "no tty" "ARG[z]"
[ ! -e "$T/tmux.args" ] && ok || bad "no tty: tmux must not be called"

# --- the bundled config parses (real tmux only, when installed) ---
if command -v tmux >/dev/null 2>&1; then
  sock="cg-tmux-test-$$"
  if tmux -L "$sock" -f "$CONF" new-session -d -s t 'sleep 5' 2>"$T/conf.err"; then
    ok
    [ "$(tmux -L "$sock" show -gv escape-time 2>/dev/null)" = 10 ] && ok || bad "tmux.conf: escape-time not applied"
  else
    bad "tmux.conf does not load: $(cat "$T/conf.err")"
  fi
  tmux -L "$sock" kill-server 2>/dev/null
fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
