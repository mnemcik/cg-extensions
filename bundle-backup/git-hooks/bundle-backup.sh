#!/bin/sh
# bundle-backup — write a `git bundle --all` of this repository to a folder.
#
# Installed by the cg bundle-backup extension as a post-commit, post-merge and
# post-rewrite script. As a hook it returns at once and does the work in the
# background, so commits never wait. Configure per repository:
#
#   git config bundle-backup.dest <folder>      # required; unset = do nothing
#   git config bundle-backup.name <name>        # default: the main worktree's dir name
#   git config bundle-backup.keepDays <n>       # daily copies kept, default 30
#
# Writes <dest>/<name>.bundle (always the latest) and
# <dest>/daily/<name>-YYYY-MM-DD.bundle (the last state of each day), and
# records the outcome in <git-common-dir>/bundle-backup.status.
set -u

if [ "${1:-}" != "--run" ]; then
	dest=$(git config --get bundle-backup.dest) || exit 0
	[ -n "$dest" ] || exit 0
	nohup "$0" --run </dev/null >/dev/null 2>&1 &
	exit 0
fi

common=$(git rev-parse --path-format=absolute --git-common-dir) || exit 1
dest=$(git --git-dir="$common" config --get bundle-backup.dest) || exit 0
name=$(git --git-dir="$common" config --get bundle-backup.name) || name=$(basename "$(dirname "$common")")
keep=$(git --git-dir="$common" config --get bundle-backup.keepDays) || keep=30
status="$common/bundle-backup.status"
lock="$common/bundle-backup.lock"
again="$common/bundle-backup.again"

record() { # record ok|error [detail]
	printf '%s %s %s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${2:-}" >"$status.$$" && mv -f "$status.$$" "$status"
}

backup() {
	if ! mkdir -p "$dest/daily" 2>/dev/null; then
		record error "cannot create $dest/daily"
		return 1
	fi
	tmp="$dest/.$name.bundle.$$.tmp"
	if ! out=$(git --git-dir="$common" bundle create "$tmp" --all 2>&1); then
		rm -f "$tmp"
		record error "git bundle create failed: $(printf '%s' "$out" | tr '\n' ' ')"
		return 1
	fi
	if ! git --git-dir="$common" bundle verify --quiet "$tmp" >/dev/null 2>&1; then
		rm -f "$tmp"
		record error "the new bundle did not verify"
		return 1
	fi
	mv -f "$tmp" "$dest/$name.bundle" || { record error "cannot write $dest/$name.bundle"; return 1; }
	day="$dest/daily/$name-$(date +%Y-%m-%d).bundle"
	cp "$dest/$name.bundle" "$day.$$.tmp" && mv -f "$day.$$.tmp" "$day"
	find "$dest/daily" -name "$name-*.bundle" -mtime +"$keep" -exec rm -f {} + 2>/dev/null
	record ok "$dest/$name.bundle"
}

# One run at a time. A run that finds the lock held asks the holder to go
# again, so a burst of commits from parallel sessions yields one or two
# bundles, not one per commit. A lock whose holder is gone is taken over.
if ! mkdir "$lock" 2>/dev/null; then
	pid=$(cat "$lock/pid" 2>/dev/null) || pid=
	if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
		: >"$again"
		exit 0
	fi
	rm -rf "$lock"
	if ! mkdir "$lock" 2>/dev/null; then
		: >"$again"
		exit 0
	fi
fi
echo $$ >"$lock/pid"
trap 'rm -rf "$lock"' EXIT INT TERM

while :; do
	rm -f "$again"
	backup || :
	[ -e "$again" ] || break
done
rm -rf "$lock"
trap - EXIT INT TERM
# A request that arrived between the last check and releasing the lock.
if [ -e "$again" ]; then
	exec "$0" --run
fi
exit 0
