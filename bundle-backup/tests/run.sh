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
mkdir "$T/dest1"
git -C "$r" config bundle-backup.dest "$T/dest1"
out=$(cd "$r" && "$check")
if [ -z "$out" ] && [ -f "$T/dest1/r1.bundle" ] && grep -q '^ok ' "$r/.git/bundle-backup.status"; then pass "check makes the first backup silently"; else fail "no silent first backup: $out"; fi
if grep -q " repaired no backup has run yet" "$r/.git/bundle-backup.log"; then pass "first backup by the check is logged"; else fail "first backup by the check not logged"; fi
git -C "$r" config --unset bundle-backup.dest

# 2. A commit writes a bundle that restores every branch and commit.
r="$T/r2"
d="$T/dest2"
newrepo "$r"
mkdir "$d"
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
#    up-to-date bundle, no leftover lock or temp files. The bundle and the
#    daily copy are written in place, so each keeps its file: a rename over
#    it would send the old file to the macOS Trash under Google Drive for
#    desktop. A hard link holds on to the old file, so a freed inode number
#    can't be reused and hide a rename (Linux reuses them at once).
day=$(ls "$d/daily/r2-"*.bundle)
ln "$b" "$T/bundle.link"
ln "$day" "$T/day.link"
git -C "$r" commit -q --amend --allow-empty -m amended
for _ in 1 2 3 4 5 6; do (cd "$r" && sh "$src" --run "$r/.git") & done
wait
wait_idle "$r"
head=$(git -C "$r" rev-parse HEAD)
if git -C "$r" bundle list-heads "$b" | grep -q "^$head refs/heads/main"; then pass "bundle holds the latest HEAD after a burst"; else fail "bundle is stale after a burst"; fi
if ls "$d"/.*.tmp "$d"/daily/.*.tmp "$r"/.git/bundle-backup.*.tmp 2>/dev/null | grep -q .; then fail "temp files left behind"; else pass "no temp files left"; fi
if [ "$b" -ef "$T/bundle.link" ]; then pass "bundle rewritten in place"; else fail "bundle replaced by a new file"; fi
if [ "$day" -ef "$T/day.link" ]; then pass "daily copy rewritten in place"; else fail "daily copy replaced by a new file"; fi
if [ ! -d "$r/.git/bundle-backup.lock" ]; then pass "lock released"; else fail "lock left behind"; fi

# 4. A lock left by a dead process is taken over.
mkdir "$r/.git/bundle-backup.lock"
echo 999999 >"$r/.git/bundle-backup.lock/pid"
git -C "$r" commit -q --allow-empty -m three
wait_idle "$r"
if git -C "$r" bundle list-heads "$b" | grep -q "^$(git -C "$r" rev-parse HEAD) "; then pass "stale lock taken over"; else fail "stale lock blocked the backup"; fi

# 5. Daily copies older than keepDays are pruned; others kept, including
#    another workspace's whose name starts the same way.
touch -t 202001010000 "$d/daily/r2-2020-01-01.bundle"
cp "$b" "$d/daily/r2-old-2020-01-01.bundle"
touch -t 202001010000 "$d/daily/r2-old-2020-01-01.bundle"
git -C "$r" commit -q --allow-empty -m four
wait_idle "$r"
if [ ! -e "$d/daily/r2-2020-01-01.bundle" ] && [ -e "$d/daily/r2-old-2020-01-01.bundle" ]; then pass "old daily copies pruned, other workspace's kept"; else fail "prune wrong"; fi

# 5b. The job still works when its starting directory and GIT_DIR are gone —
#     a session worktree removed after the land.
mkdir "$T/gone"
(cd "$T/gone" && rmdir "$T/gone" && GIT_DIR="$T/gone/.git" GIT_INDEX_FILE="$T/gone/index" sh "$src" --run "$r/.git")
if grep -q '^ok ' "$r/.git/bundle-backup.status"; then pass "runs after its worktree and GIT_DIR are removed"; else fail "fails without its worktree: $(cat "$r/.git/bundle-backup.status")"; fi

# 5c. The check repairs, silently, a backup older than the latest commit, an
#     interrupted write, and a damaged bundle; each repair is logged.
# repaired <what> <log pattern>: the check printed nothing, the status is ok,
# the bundle passes a full unpack, and the log names the repair.
repaired() {
	local out
	out=$(cd "$r" && "$check")
	rm -rf "$T/unpack"
	git init -q --bare "$T/unpack"
	if [ -z "$out" ] && grep -q '^ok ' "$r/.git/bundle-backup.status" &&
		git -C "$T/unpack" bundle unbundle "$b" >/dev/null 2>&1 &&
		grep -q " repaired $2" "$r/.git/bundle-backup.log"; then
		pass "check repairs $1 silently"
	else
		fail "check did not repair $1: ${out:-$(cat "$r/.git/bundle-backup.status")}"
	fi
}
printf 'ok 2020-01-01T00:00:00Z 1577836800 x\n' >"$r/.git/bundle-backup.status"
repaired "a stale backup" "the last backup .* is older than the latest commit"
printf 'writing 2026-01-01T00:00:00Z 4102444800 x\n' >"$r/.git/bundle-backup.status"
repaired "an interrupted write" "the last backup was interrupted while writing"
# A truncated bundle passes git bundle verify, so the check must unpack it.
ln -f "$b" "$T/bundle.link"
head -c $(($(wc -c <"$b") / 2)) "$b" >"$T/half" && cat "$T/half" >"$b"
if git -C "$r" bundle verify --quiet "$b" >/dev/null 2>&1; then echo "info git bundle verify passes the truncated bundle"; fi
repaired "a damaged bundle" ".* is damaged"
if [ "$b" -ef "$T/bundle.link" ]; then pass "repair rewrites the bundle in place"; else fail "repair replaced the bundle file"; fi
if (cd "$r" && "$check") | grep -q .; then fail "check not silent after a repair"; else pass "check silent after a repair"; fi
rm -f "$b"
repaired "a missing bundle" ".* is missing"
# A run still going after the wait is left to finish, silently: judging it
# would read a half-written bundle.
mkdir "$r/.git/bundle-backup.lock"
sleep 30 & holder=$!
echo $holder >"$r/.git/bundle-backup.lock/pid"
printf 'writing 2026-01-01T00:00:00Z 4102444800 x\n' >"$r/.git/bundle-backup.status"
out=$(cd "$r" && BUNDLE_BACKUP_WAIT=1 "$check")
if [ -z "$out" ] && grep -q "still going after 1 s; left to it" "$r/.git/bundle-backup.log"; then pass "check leaves a running backup alone"; else fail "check judged a running backup: $out"; fi
kill $holder 2>/dev/null; wait $holder 2>/dev/null
rm -rf "$r/.git/bundle-backup.lock"
repaired "the interrupted run after it" "the last backup was interrupted while writing"
# A lock over 6 hours old counts as dead even when its pid is alive (a hung
# run, or a reused pid): the check repairs instead of waiting on it forever.
mkdir "$r/.git/bundle-backup.lock"
sleep 30 & holder=$!
echo $holder >"$r/.git/bundle-backup.lock/pid"
touch -t 202001010000 "$r/.git/bundle-backup.lock"
printf 'writing 2026-01-01T00:00:00Z 4102444800 x\n' >"$r/.git/bundle-backup.status"
out=$(cd "$r" && BUNDLE_BACKUP_WAIT=1 "$check")
kill $holder 2>/dev/null; wait $holder 2>/dev/null
if [ -z "$out" ] && grep -q '^ok ' "$r/.git/bundle-backup.status"; then pass "check repairs past a lock over 6 hours old"; else fail "check stuck on an old lock: $out"; fi
# A wait that isn't a positive whole number falls back to the default
# instead of switching the check off.
for w in 0 abc 2s; do
	printf 'ok 2020-01-01T00:00:00Z 1577836800 x\n' >"$r/.git/bundle-backup.status"
	out=$(cd "$r" && BUNDLE_BACKUP_WAIT=$w "$check" 2>&1)
	if [ -z "$out" ] && grep -q '^ok .*bytes' "$r/.git/bundle-backup.status"; then pass "BUNDLE_BACKUP_WAIT=$w still checks"; else fail "BUNDLE_BACKUP_WAIT=$w: ${out:-no repair}"; fi
done
# safe.bareRepository=explicit must not break the full check.
printf '[safe]\n\tbareRepository = explicit\n' >"$T/strict.gitconfig"
GIT_CONFIG_GLOBAL="$T/strict.gitconfig" git -C "$r" commit -q --allow-empty -m strict
wait_idle "$r"
if grep -q '^ok ' "$r/.git/bundle-backup.status"; then pass "works with safe.bareRepository=explicit"; else fail "fails with safe.bareRepository=explicit: $(cat "$r/.git/bundle-backup.status")"; fi
printf 'ok 2020-01-01T00:00:00Z 1577836800 x\n' >"$r/.git/bundle-backup.status"
out=$(cd "$r" && GIT_CONFIG_GLOBAL="$T/strict.gitconfig" "$check")
if [ -z "$out" ] && grep -q '^ok ' "$r/.git/bundle-backup.status"; then pass "check repairs with safe.bareRepository=explicit"; else fail "check fails with safe.bareRepository=explicit: $out"; fi
if grep -q " start post-commit" "$r/.git/bundle-backup.log" && grep -q " start repair" "$r/.git/bundle-backup.log" &&
	grep -q " writing " "$r/.git/bundle-backup.log" && grep -q " ok .*bytes" "$r/.git/bundle-backup.log"; then
	pass "log records the trigger and each step"
else
	fail "log incomplete"
fi

# 5d. The log is trimmed once it passes 2000 lines.
seq 1 2500 | sed 's/^/old /' >>"$r/.git/bundle-backup.log"
git -C "$r" commit -q --allow-empty -m trim
wait_idle "$r"
n=$(wc -l <"$r/.git/bundle-backup.log" | tr -d ' ')
if [ "$n" -le 1010 ] && tail -n 1 "$r/.git/bundle-backup.log" | grep -q " ok "; then pass "log trimmed"; else fail "log not trimmed ($n lines)"; fi

# 6. An unwritable destination records an error and the check reports it.
r="$T/r6"
newrepo "$r"
mkdir -p "$T/ro"
: >"$T/ro/daily"
git -C "$r" config bundle-backup.dest "$T/ro"
git -C "$r" commit -q --allow-empty -m two
wait_idle "$r"
if grep -q '^error ' "$r/.git/bundle-backup.status" 2>/dev/null; then pass "failure recorded"; else fail "failure not recorded"; fi
out=$(cd "$r" && "$check")
if printf '%s' "$out" | grep -q "automatic repair failed: cannot create"; then pass "check reports a repair that failed"; else fail "check silent on a failed repair: $out"; fi
if grep -q " repair failed " "$r/.git/bundle-backup.log"; then pass "failed repair logged"; else fail "failed repair not logged"; fi
# Without the post-commit hook the check can't repair, and says so.
mv "$r/.git/hooks/post-commit" "$r/.git/hooks/post-commit.off"
if (cd "$r" && "$check") | grep -q "hook isn't installed"; then pass "check reports a missing hook"; else fail "check silent on a missing hook"; fi
# A hook that runs no backup (e.g. the script isn't approved) is reported.
printf '#!/bin/sh\nexit 0\n' >"$r/.git/hooks/post-commit"
chmod +x "$r/.git/hooks/post-commit"
if (cd "$r" && "$check") | grep -q "but no backup ran"; then pass "check reports that no backup ran"; else fail "check silent when no backup ran"; fi
mv "$r/.git/hooks/post-commit.off" "$r/.git/hooks/post-commit"
git -C "$r" config bundle-backup.dest "$T/missing-mount"
if (cd "$r" && "$check") | grep -q "does not exist"; then pass "check reports a missing destination"; else fail "check silent on missing destination"; fi

# 6b. A missing destination (sync folder not mounted) is an error, and is not
#     created behind the user's back.
git -C "$r" commit -q --allow-empty -m three
wait_idle "$r"
if [ ! -e "$T/missing-mount" ] && grep -q "does not exist" "$r/.git/bundle-backup.status"; then pass "missing destination not created, error recorded"; else fail "missing destination handled wrong"; fi

# 6c. A relative destination is rejected; ~ is expanded.
r="$T/r6c"
newrepo "$r"
git -C "$r" config bundle-backup.dest "relative/dir"
git -C "$r" commit -q --allow-empty -m two
wait_idle "$r"
if grep -q "must be an absolute path" "$r/.git/bundle-backup.status" 2>/dev/null; then pass "relative destination rejected"; else fail "relative destination accepted"; fi
if (cd "$r" && "$check") | grep -q "must be an absolute path"; then pass "check reports a relative destination"; else fail "check silent on a relative destination"; fi
mkdir -p "$T/home/bk"
git -C "$r" config bundle-backup.dest "~/bk"
(export HOME="$T/home"; git -C "$r" commit -q --allow-empty -m three; wait_idle "$r")
if [ -f "$T/home/bk/r6c.bundle" ]; then pass "~ in the destination expanded"; else fail "~ not expanded: $(cat "$r/.git/bundle-backup.status")"; fi

# 6d. Installed in .git/hooks, git runs the hook by a relative path; the
#     re-exec after the lock is released must still find the script.
r="$T/r6d"
d="$T/dest6d"
newrepo "$r"
mkdir "$d"
git -C "$r" config bundle-backup.dest "$d"
mkdir "$r/.git/bundle-backup.lock"
sleep 30 & holder=$!
echo $holder >"$r/.git/bundle-backup.lock/pid"
git -C "$r" commit -q --allow-empty -m queued
sleep 0.5
kill $holder 2>/dev/null; wait $holder 2>/dev/null
(cd "$r" && sh .git/hooks/post-commit)
wait_idle "$r"
if git -C "$r" bundle list-heads "$d/r6d.bundle" 2>/dev/null | grep -q "^$(git -C "$r" rev-parse HEAD) "; then pass "relative hook path works"; else fail "relative hook path broke the run"; fi

# 7. A commit in a linked worktree backs up the whole repository.
r="$T/r7"
d="$T/dest7"
newrepo "$r"
mkdir "$d"
git -C "$r" config bundle-backup.dest "$d"
git -C "$r" worktree add -q -b session/x "$T/r7--x"
git -C "$T/r7--x" commit -q --allow-empty -m "from worktree"
wait_idle "$r"
if git -C "$r" bundle list-heads "$d/r7.bundle" 2>/dev/null | grep -q "refs/heads/session/x"; then pass "worktree commit backed up under the main name"; else fail "worktree commit not backed up"; fi

echo
if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
