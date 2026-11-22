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

# A cg 2.0+ session running this suite must not change what the launcher sees.
unset CG_WORKSPACE

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

[ -z "$(grep -x -- -e "$T/tmux.args")" ] && ok || bad "CG_WORKSPACE unset: -e must not be passed: $args"

# --- CG_WORKSPACE (cg 2.0+): passed into the new session with -e ---
( cd "$T/my.work:space" && env -u TMUX CG_WORKSPACE="$T/the ws" CG_TMUX_ASSUME_TTY=1 CG_TMUX_BIN="$T/tmux" "$LAUNCH" launch -- "$T/agent" x )
tail_want=$(printf '%s\n' -e "CG_WORKSPACE=$T/the ws" -c "$(cd "$T/my.work:space" && pwd)" -- "$T/agent" x)
[ "$(sed -n '8,$p' "$T/tmux.args")" = "$tail_want" ] && ok || bad "CG_WORKSPACE set: tail args: $(sed -n '8,$p' "$T/tmux.args")"
# set but empty: nothing to pass
( env -u TMUX CG_WORKSPACE= CG_TMUX_ASSUME_TTY=1 CG_TMUX_BIN="$T/tmux" "$LAUNCH" launch -- "$T/agent" )
[ -z "$(grep -x -- -e "$T/tmux.args")" ] && ok || bad "CG_WORKSPACE empty: -e must not be passed: $(cat "$T/tmux.args")"

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
  if tmux -L "$sock" -f "$CONF" new-session -d -s t 'sleep 60' 2>"$T/conf.err"; then
    ok
    [ "$(tmux -L "$sock" show -gv escape-time 2>/dev/null)" = 10 ] && ok || bad "tmux.conf: escape-time not applied"
    # a failing line doesn't fail new-session (tmux carries on); source-file reports it
    if tmux -L "$sock" source-file "$CONF" 2>"$T/conf.err" && [ ! -s "$T/conf.err" ]; then ok; else bad "tmux.conf has an error: $(head -1 "$T/conf.err")"; fi
    [ "$(tmux -L "$sock" show -gv set-titles 2>/dev/null)" = on ] && ok || bad "tmux.conf: set-titles not applied"
    [ "$(tmux -L "$sock" show -gv set-titles-string 2>/dev/null)" = '#T' ] && ok || bad "tmux.conf: set-titles-string not applied"
    if tmux -L "$sock" show -gwv allow-passthrough >/dev/null 2>&1; then
      ap=$(tmux -L "$sock" show -gwv allow-passthrough 2>/dev/null); want=on
      [ "$(tmux -L "$sock" display -p -t t '#{e|>=|f|0:#{s/[^0-9.]//:version},3.4}' 2>/dev/null)" = 1 ] && want=all
      [ "$ap" = "$want" ] && ok || bad "tmux.conf: allow-passthrough is '$ap', want '$want'"
    fi
  else
    bad "tmux.conf does not load: $(cat "$T/conf.err")"
  fi

  # CG_WORKSPACE reaches the agent in a session on a server that is already
  # running, whose environment doesn't have it (tmux copies only PATH and its
  # update-environment list from the client). A wrapper adds -d so nothing attaches.
  cat > "$T/tmux-detached" <<'W'
#!/bin/sh
for a; do shift; if [ "$a" = new-session ]; then set -- "$@" new-session -d; else set -- "$@" "$a"; fi; done
exec tmux "$@"
W
  cat > "$T/agent-env" <<A
#!/bin/sh
printf '%s' "\${CG_WORKSPACE-unset}" > "$T/agent.ws.tmp" && mv "$T/agent.ws.tmp" "$T/agent.ws"
A
  chmod +x "$T/tmux-detached" "$T/agent-env"
  for ws in "$T/ws one" ""; do
    rm -f "$T/agent.ws"
    if [ -n "$ws" ]; then
      env -u TMUX CG_WORKSPACE="$ws" CG_TMUX_SOCKET="$sock" CG_TMUX_ASSUME_TTY=1 CG_TMUX_BIN="$T/tmux-detached" "$LAUNCH" launch -- "$T/agent-env" >/dev/null 2>&1
      want=$ws
    else
      env -u TMUX -u CG_WORKSPACE CG_TMUX_SOCKET="$sock" CG_TMUX_ASSUME_TTY=1 CG_TMUX_BIN="$T/tmux-detached" "$LAUNCH" launch -- "$T/agent-env" >/dev/null 2>&1
      want=unset
    fi
    i=0; while [ ! -e "$T/agent.ws" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
    got=$(cat "$T/agent.ws" 2>/dev/null)
    [ "$got" = "$want" ] && ok || bad "real tmux: the agent's CG_WORKSPACE is '$got', want '$want'"
  done
  tmux -L "$sock" kill-server 2>/dev/null
fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
