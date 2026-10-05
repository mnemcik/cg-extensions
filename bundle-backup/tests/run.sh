#!/bin/bash
# Test suite for git-hooks/bundle-backup.sh and hooks/status.sh, against
# throwaway repositories. Runs the script the way the cg dispatcher does.
set -u
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../git-hooks/bundle-backup.sh"
check="$here/../hooks/status.sh"

T=$(mktemp -d "${TMPDIR:-/tmp}/bb-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# newrepo <dir>: a repository with one commit on main and the script installed
# as post-commit, post-merge and post-rewrite hooks.
newrepo() {
	git init -q -b main "$1"
	git -C "$1" config user.email t@example.com
	git -C "$1" config user.name T
	git -C "$1" config commit.gpgsign false
	git -C "$1" commit -q --allow-empty -m init
	for h in post-commit post-merge post-rewrite; do
		cp "$src" "$1/.git/hooks/$h"
		chmod +x "$1/.git/hooks/$h"
	done
}

# wait_idle <repo>: wait for background runs to finish (lock gone, no request).
wait_idle() {
	for _ in $(seq 1 200); do
		[ ! -d "$1/.git/bundle-backup.lock" ] && [ ! -e "$1/.git/bundle-backup.again" ] && sleep 0.2 &&
			[ ! -d "$1/.git/bundle-backup.lock" ] && return 0
		sleep 0.05
	done
	return 1
}

# 1. Unset destination: a commit writes nothing, and the check says so.
r="$T/r1"
newrepo "$r"
git -C "$r" commit -q --allow-empty -m two
sleep 0.3
if [ ! -e "$r/.git/bundle-backup.status" ]; then pass "unset dest does nothing"; else fail "unset dest wrote a status"; fi
if (cd "$r" && "$check") | grep -q "no destination set"; then pass "check reports unset dest"; else fail "check silent on unset dest"; fi

# 2. A commit writes a bundle that restores every branch and commit.
r="$T/r2"
d="$T/dest2"
newrepo "$r"
git -C "$r" config bundle-backup.dest "$d"
git -C "$r" branch side
git -C "$r" commit -q --allow-empty -m two
wait_idle "$r"
b="$d/r2.bundle"
if [ -f "$b" ] && git -C "$r" bundle verify --quiet "$b" 2>/dev/null; then pass "commit writes a valid bundle"; else fail "no valid bundle after commit"; fi
git clone -q --mirror "$b" "$T/restore2.git" 2>/dev/null
if [ "$(git -C "$T/restore2.git" rev-list --all --count)" = "$(git -C "$r" rev-list --all --count)" ] &&
	git -C "$T/restore2.git" rev-parse -q --verify refs/heads/side >/dev/null; then
	pass "mirror clone restores all commits and branches"
else
	fail "restore is missing commits or branches"
fi
if ls "$d/daily/r2-"*.bundle >/dev/null 2>&1; then pass "daily copy written"; else fail "no daily copy"; fi
if grep -q '^ok ' "$r/.git/bundle-backup.status"; then pass "status records ok"; else fail "status not ok: $(cat "$r/.git/bundle-backup.status")"; fi
if (cd "$r" && "$check") | grep -q .; then fail "check not silent when healthy"; else pass "check silent when healthy"; fi

# 3. Amend (post-rewrite) and a burst of concurrent runs end with one
#    up-to-date bundle, no leftover lock or temp files.
git -C "$r" commit -q --amend --allow-empty -m amended
for _ in 1 2 3 4 5 6; do (cd "$r" && "$src" --run) & done
wait
wait_idle "$r"
head=$(git -C "$r" rev-parse HEAD)
if git -C "$r" bundle list-heads "$b" | grep -q "^$head refs/heads/main"; then pass "bundle holds the latest HEAD after a burst"; else fail "bundle is stale after a burst"; fi
if ls "$d"/.*.tmp >/dev/null 2>&1; then fail "temp files left behind"; else pass "no temp files left"; fi
if [ ! -d "$r/.git/bundle-backup.lock" ]; then pass "lock released"; else fail "lock left behind"; fi

# 4. A lock left by a dead process is taken over.
mkdir "$r/.git/bundle-backup.lock"
echo 999999 >"$r/.git/bundle-backup.lock/pid"
git -C "$r" commit -q --allow-empty -m three
wait_idle "$r"
if git -C "$r" bundle list-heads "$b" | grep -q "^$(git -C "$r" rev-parse HEAD) "; then pass "stale lock taken over"; else fail "stale lock blocked the backup"; fi

# 5. Daily copies older than keepDays are pruned; others kept.
touch -t 202001010000 "$d/daily/r2-2020-01-01.bundle"
cp "$b" "$d/daily/r2-recent.bundle"
git -C "$r" commit -q --allow-empty -m four
wait_idle "$r"
if [ ! -e "$d/daily/r2-2020-01-01.bundle" ] && [ -e "$d/daily/r2-recent.bundle" ]; then pass "old daily copies pruned"; else fail "prune wrong"; fi

# 6. An unwritable destination records an error and the check reports it.
r="$T/r6"
newrepo "$r"
: >"$T/notadir"
git -C "$r" config bundle-backup.dest "$T/notadir/sub"
git -C "$r" commit -q --allow-empty -m two
wait_idle "$r"
if grep -q '^error ' "$r/.git/bundle-backup.status" 2>/dev/null; then pass "failure recorded"; else fail "failure not recorded"; fi
git -C "$r" config bundle-backup.dest "$T"
if (cd "$r" && "$check") | grep -q "last backup failed"; then pass "check reports the failure"; else fail "check silent on failure"; fi
git -C "$r" config bundle-backup.dest "$T/missing-mount"
if (cd "$r" && "$check") | grep -q "does not exist"; then pass "check reports a missing destination"; else fail "check silent on missing destination"; fi

# 7. A commit in a linked worktree backs up the whole repository.
r="$T/r7"
d="$T/dest7"
newrepo "$r"
git -C "$r" config bundle-backup.dest "$d"
git -C "$r" worktree add -q -b session/x "$T/r7--x"
git -C "$T/r7--x" commit -q --allow-empty -m "from worktree"
wait_idle "$r"
if git -C "$r" bundle list-heads "$d/r7.bundle" 2>/dev/null | grep -q "refs/heads/session/x"; then pass "worktree commit backed up under the main name"; else fail "worktree commit not backed up"; fi

echo
if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
