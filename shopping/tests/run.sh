#!/usr/bin/env bash
# Test suite for bin/cg-shop. Runs in throwaway git repos; never touches the
# caller's workspace.
#
#   tests/run.sh

set -u
here=$(cd "$(dirname "$0")" && pwd)
SHOP="$here/../bin/cg-shop"

T=$(mktemp -d "${TMPDIR:-/tmp}/cg-shop-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

pass=0 fail=0
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); printf 'FAIL: %s\n' "$*" >&2; }

# expect NAME WANT_EXIT CMD... — run CMD, capture stdout+stderr in $out.
expect() {
  local name=$1 want=$2; shift 2
  out=$("$@" 2>&1); local got=$?
  if [ "$got" -eq "$want" ]; then ok; else bad "$name: exit $got, want $want; output: $out"; fi
}
contains() { case "$out" in *"$2"*) ok ;; *) bad "$1: output lacks '$2'; output: $out" ;; esac; }
lacks()    { case "$out" in *"$2"*) bad "$1: output has '$2'; output: $out" ;; *) ok ;; esac; }
file_has() { if grep -qxF -- "$3" "$2"; then ok; else bad "$1: $2 lacks line '$3'"; fi; }

newrepo() {
  rm -rf "$T/ws"; mkdir -p "$T/ws"; cd "$T/ws" || exit 1
  git init -q -b main; git commit -q --allow-empty -m init
}

export CG_SHOP_TODAY=2026-11-13
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset CG_SHOP_DIR

# ---------------------------------------------------------------- add
newrepo
expect "add basic" 0 "$SHOP" add "ESP32-C6 module" --supplier LCSC --qty 10 --project "Weather Station" --part C5366877
contains "add prints id" "added 2026-11-13-esp32-c6-module"
f=shopping/2026-11-13-esp32-c6-module.md
[ -f "$f" ] && ok || bad "add: $f not created"
file_has "add title" "$f" 'title: "ESP32-C6 module"'
file_has "add status" "$f" 'status: needed'
file_has "add supplier slug" "$f" 'supplier: "lcsc"'
file_has "add qty" "$f" 'qty: 10'
file_has "add project slug" "$f" 'project: "weather-station"'
file_has "add part" "$f" 'part: "C5366877"'
file_has "add added" "$f" 'added: 2026-11-13'

expect "add quotes and note" 0 "$SHOP" add 'Resistor 10k "0603" \ pack' -s lcsc -q 100 -p weather-station --note "any brand"
g=shopping/2026-11-13-resistor-10k-0603-pack.md
file_has "add escapes" "$g" 'title: "Resistor 10k \"0603\" \\ pack"'
file_has "add note body" "$g" 'any brand'

expect "add same title twice" 0 "$SHOP" add "ESP32-C6 module" --supplier lcsc
contains "duplicate gets suffix" "added 2026-11-13-esp32-c6-module-"
[ "$(ls shopping | grep -c '^2026-11-13-esp32-c6-module')" -eq 2 ] && ok || bad "duplicate title should make a second file"

expect "add needs supplier" 2 "$SHOP" add "thing"
expect "add needs title" 2 "$SHOP" add --supplier lcsc
expect "add rejects qty 0" 2 "$SHOP" add thing -s lcsc -q 0
expect "add rejects qty text" 2 "$SHOP" add thing -s lcsc -q ten
expect "add rejects bad date" 2 "$SHOP" add thing -s lcsc --needed-by 13.11.2026
expect "add unknown option" 2 "$SHOP" add thing -s lcsc --colour red
expect "add dev kit" 0 "$SHOP" add "Dev kit" -s DigiKey -p lamp --needed-by 2026-12-01

# ---------------------------------------------------------------- list
expect "list default" 0 "$SHOP" list
contains "list groups digikey" "digikey (1 needed)"
contains "list groups lcsc" "lcsc (3 needed)"
contains "list shows part" "[C5366877]"
contains "list shows needed-by" "by 2026-12-01"
contains "list unescapes title" 'Resistor 10k "0603" \ pack'
expect "list by project" 0 "$SHOP" list --by project
contains "list by project, no project group" "(no project) (1 needed)"
contains "list by project, lamp" "lamp (1 needed)"
expect "list filter supplier" 0 "$SHOP" list --supplier LCSC
lacks "list filter excludes digikey" "Dev kit"
expect "list filter project" 0 "$SHOP" list --project lamp
lacks "list project filter excludes lcsc" "ESP32"
expect "list tsv" 0 "$SHOP" list --tsv
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 5 ] && ok || bad "list --tsv: want header + 4 rows; got: $out"
expect "list bad --by" 2 "$SHOP" list --by colour
expect "list bad --status" 2 "$SHOP" list --status lost

# ---------------------------------------------------------------- order
expect "order nothing from unknown supplier" 1 "$SHOP" order mouser
expect "order needs supplier" 2 "$SHOP" order
expect "order lcsc" 0 "$SHOP" order LCSC --ref LC123
contains "order count" "3 item(s) from lcsc marked ordered (order LC123)"
file_has "order status" "$f" 'status: ordered'
file_has "order date" "$f" 'ordered: 2026-11-13'
file_has "order ref" "$f" 'order_ref: "LC123"'
file_has "order keeps fields" "$f" 'part: "C5366877"'
[ "$(grep -c '^status:' "$f")" -eq 1 ] && ok || bad "order: status line duplicated in $f"
expect "order again: nothing left" 1 "$SHOP" order lcsc
expect "list after order" 0 "$SHOP" list
contains "list shows ordered group" "lcsc (3 ordered)"
contains "list shows order ref" "order LC123"

# order restricted to ids
expect "add two more" 0 "$SHOP" add "Header pins" -s lcsc
expect "add two more" 0 "$SHOP" add "Jumper wires" -s lcsc
expect "order one id" 0 "$SHOP" order lcsc 2026-11-13-header
contains "order one id count" "1 item(s) from lcsc marked ordered"
file_has "the other stays needed" shopping/2026-11-13-jumper-wires.md 'status: needed'
expect "order id of another supplier" 1 "$SHOP" order lcsc 2026-11-13-dev-kit

# ---------------------------------------------------------------- receive / cancel
expect "ambiguous prefix" 1 "$SHOP" receive 2026-11-13-esp
contains "ambiguous names matches" "matches 2 items"
expect "unknown id" 1 "$SHOP" receive nope
expect "receive by ref" 0 "$SHOP" receive --ref LC123
file_has "receive status" "$f" 'status: received'
file_has "receive date" "$f" 'received: 2026-11-13'
file_has "receive keeps project" "$f" 'project: "weather-station"'
expect "receive unknown ref" 1 "$SHOP" receive --ref NOPE
expect "receive by id" 0 "$SHOP" receive 2026-11-13-header
expect "receive twice is a no-op" 0 "$SHOP" receive 2026-11-13-header
contains "receive twice says so" "already received"
expect "cancel" 0 "$SHOP" cancel 2026-11-13-dev
file_has "cancel status" shopping/2026-11-13-dev-kit.md 'status: cancelled'
expect "cannot receive cancelled" 1 "$SHOP" receive 2026-11-13-dev
expect "cannot cancel received" 1 "$SHOP" cancel 2026-11-13-header
expect "cancel takes no ref" 2 "$SHOP" cancel --ref LC123
expect "receive needs ids" 2 "$SHOP" receive

expect "list open hides closed" 0 "$SHOP" list
lacks "open hides received" "received"
lacks "open hides cancelled" "Dev kit"
contains "open keeps needed" "Jumper wires"
expect "list all" 0 "$SHOP" list --all --by none
contains "all shows cancelled" "cancelled    1 x Dev kit"
contains "all shows received" "received    10 x ESP32-C6 module"
expect "list status filter" 0 "$SHOP" list --status received --tsv
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 5 ] && ok || bad "list --status received: want header + 4 rows; got: $out"

expect "show" 0 "$SHOP" show 2026-11-13-jumper
contains "show prints file" 'title: "Jumper wires"'

# ---------------------------------------------------------------- misc
expect "help" 0 "$SHOP" help
expect "no args is help" 0 "$SHOP"
expect "unknown command" 2 "$SHOP" frobnicate
expect "version" 0 "$SHOP" version
expect "empty list" 0 env CG_SHOP_DIR="$T/empty" "$SHOP" list
contains "empty list says so" "No items."
mkdir -p "$T/nogit"
out=$(cd "$T/nogit" && GIT_CEILING_DIRECTORIES="$T" "$SHOP" list 2>&1)
[ $? -eq 1 ] && ok || bad "outside git should exit 1: $out"

# A file someone edited by hand (single quotes, no quotes, extra keys) still reads.
cat >shopping/2026-11-12-hand-written.md <<'EOF'
---
title: Soldering tips
status: needed
supplier: 'local-shop'
qty: 3
colour: red
---
EOF
expect "hand-written file" 0 "$SHOP" list --supplier local-shop
contains "hand-written file reads" "3 x Soldering tips"

# ---------------------------------------------------------------- parallel worktrees land cleanly
# The design claim: two sessions adding items in separate worktrees never conflict.
newrepo
git worktree add -q -b s1 "$T/w1" && git worktree add -q -b s2 "$T/w2"
(cd "$T/w1" && "$SHOP" add "Item one" -s lcsc >/dev/null && git add shopping && git commit -q -m one)
(cd "$T/w2" && "$SHOP" add "Item two" -s lcsc >/dev/null && git add shopping && git commit -q -m two)
git merge -q --ff-only s1
if (cd "$T/w2" && git rebase -q main >/dev/null 2>&1); then ok; else bad "parallel adds conflicted on rebase"; fi
git merge -q --ff-only s2
expect "both items after landing" 0 "$SHOP" list
contains "item one landed" "Item one"
contains "item two landed" "Item two"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
