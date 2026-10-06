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
# records the outcome in <git-common-dir>/bundle-backup.status as
# "ok|error <ISO time> <epoch> <detail>".
set -u

if [ "${1:-}" != "--run" ]; then
	dest=$(git config --get bundle-backup.dest) || exit 0
	[ -n "$dest" ] || exit 0
	common=$(git rev-parse --path-format=absolute --git-common-dir) || exit 0
	# sh, not "$0": the script may lack the execute bit.
	nohup sh "$0" --run "$common" </dev/null >/dev/null 2>&1 &
	exit 0
fi

# Detach from the hook's checkout and environment. The job outlives the hook,
# and a session worktree it was started from may be removed meanwhile.
common=${2:-}
[ -n "$common" ] && [ -d "$common" ] || exit 1
cd "$common" || exit 1
GIT_DIR=$common
export GIT_DIR
unset GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX

dest=$(git config --get bundle-backup.dest) || exit 0
name=$(git config --get bundle-backup.name) || name=$(basename "$(git worktree list --porcelain | sed -n '1s/^worktree //p')")
keep=$(git config --get bundle-backup.keepDays) || keep=30
status="$common/bundle-backup.status"
lock="$common/bundle-backup.lock"
again="$common/bundle-backup.again"

record() { # record ok|error [detail]
	printf '%s %s %s %s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date +%s)" "${2:-}" >"$status.$$" && mv -f "$status.$$" "$status"
}

backup() {
	# The destination must already exist: creating it would hide a sync
	# folder that is not mounted behind a local, unsynced copy.
	if [ ! -d "$dest" ]; then
		record error "destination $dest does not exist (is the sync folder mounted?)"
		return 1
	fi
	if ! mkdir -p "$dest/daily" 2>/dev/null; then
		record error "cannot create $dest/daily"
		return 1
	fi
	# Temp files left by a run that was killed.
	find "$dest" "$dest/daily" -maxdepth 1 -type f -name ".$name.*.tmp" -mmin +60 -exec rm -f {} + 2>/dev/null
	tmp="$dest/.$name.bundle.$$.tmp"
	if ! out=$(git bundle create "$tmp" --all 2>&1); then
		rm -f "$tmp"
		record error "git bundle create failed: $(printf '%s' "$out" | tr '\n' ' ')"
		return 1
	fi
	if ! git bundle verify --quiet "$tmp" >/dev/null 2>&1; then
		rm -f "$tmp"
		record error "the new bundle did not verify"
		return 1
	fi
	mv -f "$tmp" "$dest/$name.bundle" || { record error "cannot write $dest/$name.bundle"; return 1; }
	day="$dest/daily/$name-$(date +%Y-%m-%d).bundle"
	dtmp="$dest/daily/.$name.daily.$$.tmp"
	if ! { cp "$dest/$name.bundle" "$dtmp" && mv -f "$dtmp" "$day"; }; then
		rm -f "$dtmp"
		record error "latest bundle written, but the daily copy $day failed"
		return 1
	fi
	find "$dest/daily" -maxdepth 1 -type f -name "$name-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].bundle" -mtime +"$keep" -exec rm -f {} + 2>/dev/null
	record ok "$dest/$name.bundle"
}

# One run at a time. A run that finds the lock held asks the holder to go
# again, so a burst of commits from parallel sessions yields one or two
# bundles, not one per commit. The lock is taken over when its process is
# gone, or when it is over 6 hours old (a crashed run whose pid was reused).
# A lock with no pid yet belongs to a run that has just taken it.
stale() {
	[ -n "$(find "$lock" -maxdepth 0 -mmin +360 2>/dev/null)" ] && return 0
	pid=$(cat "$lock/pid" 2>/dev/null) || pid=
	[ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null
}
if ! mkdir "$lock" 2>/dev/null; then
	if ! stale; then
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
trap 'rm -rf "$lock"' EXIT
trap 'rm -rf "$lock"; exit 1' INT TERM

while :; do
	rm -f "$again"
	backup || :
	[ -e "$again" ] || break
done
rm -rf "$lock"
trap - EXIT INT TERM
# A request that arrived between the last check and releasing the lock.
if [ -e "$again" ]; then
	exec sh "$0" --run "$common"
fi
exit 0
