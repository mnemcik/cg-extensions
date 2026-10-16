#!/bin/sh
# bundle-backup — write a `git bundle --all` of this repository to a folder.
#
# Installed by the cg bundle-backup extension as a post-commit, post-merge and
# post-rewrite script. As a hook it returns at once and does the work in the
# background, so commits never wait. Configure per repository:
#
#   git config bundle-backup.dest <folder>      # required, absolute (~ ok); unset = do nothing
#   git config bundle-backup.name <name>        # default: the main worktree's dir name
#   git config bundle-backup.keepDays <n>       # daily copies kept, default 30
#
# Writes <dest>/<name>.bundle (always the latest) and
# <dest>/daily/<name>-YYYY-MM-DD.bundle (the last state of each day), records
# the outcome in <git-common-dir>/bundle-backup.status as
# "ok|writing|error <ISO time> <epoch> <detail>", and appends every step to
# <git-common-dir>/bundle-backup.log.
#
# The SessionStart check (hooks/status.sh) repairs a failed, interrupted or
# damaged backup by running this hook in the foreground:
#   BUNDLE_BACKUP_FOREGROUND=1  run in the foreground instead of the background
#   BUNDLE_BACKUP_TRIGGER=<why> what started the run, for the log
set -u

# This script's absolute path, for the background job and its re-exec, which
# run after a cd.
self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

if [ "${1:-}" != "--run" ]; then
	dest=$(git config --type=path --get bundle-backup.dest) || exit 0
	[ -n "$dest" ] || exit 0
	common=$(git rev-parse --path-format=absolute --git-common-dir) || exit 0
	# The hook that ran us: the dispatcher runs this script from
	# .cg/git-hooks/<hook>.d/, a plain install is .git/hooks/<hook>.
	hook=$(basename "$(dirname "$0")")
	case "$hook" in
	*.d) hook=${hook%.d} ;;
	*) hook=$(basename "$0") ;;
	esac
	trigger=${BUNDLE_BACKUP_TRIGGER:-$hook}
	# sh, not "$0": the script may lack the execute bit.
	if [ -n "${BUNDLE_BACKUP_FOREGROUND:-}" ]; then
		sh "$self" --run "$common" "$trigger" </dev/null >/dev/null 2>&1
		exit 0
	fi
	nohup sh "$self" --run "$common" "$trigger" </dev/null >/dev/null 2>&1 &
	exit 0
fi

# Detach from the hook's checkout and environment. The job outlives the hook,
# and a session worktree it was started from may be removed meanwhile.
common=${2:-}
trigger=${3:-unknown}
[ -n "$common" ] && [ -d "$common" ] || exit 1
cd "$common" || exit 1
GIT_DIR=$common
export GIT_DIR
unset GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX

dest=$(git config --type=path --get bundle-backup.dest) || exit 0
name=$(git config --get bundle-backup.name) || name=$(basename "$(git worktree list --porcelain | sed -n '1s/^worktree //p')")
keep=$(git config --get bundle-backup.keepDays) || keep=30
status="$common/bundle-backup.status"
log="$common/bundle-backup.log"
lock="$common/bundle-backup.lock"
again="$common/bundle-backup.again"
tmp="$common/bundle-backup.$$.tmp"
check="$common/bundle-backup.check.$$"

# log <event> [detail]: one line per step, kept for investigating problems
# later. Local to this machine and never synced.
log() {
	printf '%s %s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" "$1" "${2:-}" >>"$log" 2>/dev/null
}

record() { # record ok|writing|error [detail]
	printf '%s %s %s %s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date +%s)" "${2:-}" >"$status.$$" && mv -f "$status.$$" "$status"
	log "$1" "${2:-}"
}

# put <src> <file>: write src into file in place and check the copy. A rename
# over the file would leave a new file in its place, and Google Drive for
# desktop moves the file it replaced to the macOS Trash. Writing in place keeps
# the file, so Drive records a new version of it instead.
put() {
	cat "$1" >"$2" && cmp -s "$1" "$2"
}

# full_check <bundle>: unpack every object of the bundle into a throwaway
# repository. git bundle verify reads only the header and passes a truncated
# or damaged bundle; unbundling checks each object.
full_check() {
	rm -rf "$check"
	(
		unset GIT_DIR
		# --git-dir, not discovery: safe.bareRepository=explicit refuses a
		# bare repository found by discovery.
		git init -q --bare "$check" >/dev/null 2>&1 &&
			git --git-dir="$check" bundle unbundle "$1" >/dev/null 2>&1
	)
	rc=$?
	rm -rf "$check"
	return $rc
}

# live_heads: the refs git bundle create --all writes, one "<oid> <ref>" per
# line and sorted: every ref of the repository, HEAD, and the HEAD of each
# linked worktree that resolves. Read from the common git dir, so a linked
# worktree's own HEAD and per-worktree refs don't leak in. The SessionStart
# check builds the same list.
live_heads() {
	(
		GIT_DIR=$common
		export GIT_DIR
		git for-each-ref --format='%(objectname) %(refname)'
		h=$(git rev-parse -q --verify HEAD 2>/dev/null) && echo "$h HEAD"
		for w in "$common"/worktrees/*/; do
			[ -d "$w" ] || continue
			id=$(basename "$w")
			h=$(git rev-parse -q --verify "worktrees/$id/HEAD" 2>/dev/null) && echo "$h worktrees/$id/HEAD"
		done
	) | LC_ALL=C sort
}

backup() {
	case "$dest" in
	/*) ;;
	*)
		record error "bundle-backup.dest must be an absolute path (got $dest)"
		return 1
		;;
	esac
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
	# Temp files left by a run that was killed, including the lock file git
	# bundle create writes through. Up to 0.1.1 they were written in the
	# destination.
	find "$common" -maxdepth 1 -type f \( -name "bundle-backup.*.tmp" -o -name "bundle-backup.*.tmp.lock" \) -mmin +60 -exec rm -f {} + 2>/dev/null
	find "$common" -maxdepth 1 -type d -name "bundle-backup.check.*" -mmin +60 -exec rm -rf {} + 2>/dev/null
	find "$dest" "$dest/daily" -maxdepth 1 -type f -name ".$name.*.tmp" -mmin +60 -exec rm -f {} + 2>/dev/null
	# Build and check in the git dir, outside the synced folder, then write
	# into the destination in place. That write is not atomic; see put.
	if ! out=$(git bundle create "$tmp" --all 2>&1); then
		rm -f "$tmp"
		record error "git bundle create failed: $(printf '%s' "$out" | tr '\n' ' ')"
		return 1
	fi
	if ! full_check "$tmp"; then
		rm -f "$tmp"
		record error "the new bundle failed its check"
		return 1
	fi
	# "writing" until the copies are done: a run killed while writing leaves
	# it behind, and the SessionStart check repairs the backup.
	record writing "$dest/$name.bundle"
	if ! put "$tmp" "$dest/$name.bundle"; then
		rm -f "$tmp"
		record error "cannot write $dest/$name.bundle"
		return 1
	fi
	day="$dest/daily/$name-$(date +%Y-%m-%d).bundle"
	if ! put "$tmp" "$day"; then
		rm -f "$tmp"
		record error "latest bundle written, but the daily copy $day failed"
		return 1
	fi
	# Refs moved while the bundle was made, by a command that fires no hook
	# (branch -f, reset, update-ref): go once more. At most twice per run, so
	# a difference that never goes away can't loop.
	if [ "$moved" -lt 2 ] && [ "$(git bundle list-heads "$tmp" 2>/dev/null | LC_ALL=C sort)" != "$(live_heads)" ]; then
		moved=$((moved + 1))
		: >"$again"
		log "refs moved" "during the run; going once more"
	fi
	size=$(wc -c <"$tmp" | tr -d ' ')
	rm -f "$tmp"
	find "$dest/daily" -maxdepth 1 -type f -name "$name-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].bundle" -mtime +"$keep" -exec rm -f {} + 2>/dev/null
	record ok "$dest/$name.bundle ($size bytes, $(git rev-parse --short HEAD 2>/dev/null))"
}

# Keep the log to the last 1000 lines once it passes 2000.
trim_log() {
	[ -f "$log" ] || return 0
	[ "$(wc -l <"$log")" -gt 2000 ] || return 0
	tail -n 1000 "$log" >"$log.$$" && mv -f "$log.$$" "$log"
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
		log queued "$trigger"
		exit 0
	fi
	log "lock taken over" "pid $(cat "$lock/pid" 2>/dev/null)"
	rm -rf "$lock"
	if ! mkdir "$lock" 2>/dev/null; then
		: >"$again"
		log queued "$trigger"
		exit 0
	fi
fi
echo $$ >"$lock/pid"
moved=0
trap 'rm -rf "$lock" "$check"; rm -f "$tmp"' EXIT
trap 'rm -rf "$lock" "$check"; rm -f "$tmp"; log killed "$trigger"; exit 1' INT TERM

while :; do
	rm -f "$again"
	log start "$trigger"
	backup || :
	[ -e "$again" ] || break
	trigger=rerun
done
trim_log
rm -rf "$lock"
trap - EXIT INT TERM
# A request that arrived between the last check and releasing the lock.
if [ -e "$again" ]; then
	exec sh "$self" --run "$common" rerun
fi
exit 0
