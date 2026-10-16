#!/usr/bin/env bash
# bundle-backup SessionStart check. Repairs the backup without involving the
# user when it can: no backup yet, a failed or interrupted last run, a backup
# older than the latest commit, or a missing or damaged bundle in the
# destination each start a backup run in the foreground, through the same
# post-commit hook a commit runs. Says something only when the user has to act:
# backups not configured, the destination missing (e.g. the sync folder is not
# mounted), the hook not installed, or a repair that failed. Every decision is
# appended to <git-common-dir>/bundle-backup.log.
dest=$(git config --type=path --get bundle-backup.dest 2>/dev/null) || dest=
if [ -z "$dest" ]; then
	echo "bundle-backup: no destination set, so this workspace is not being backed up. Set one with: git config bundle-backup.dest <folder>"
	exit 0
fi
case "$dest" in
/*) ;;
*)
	echo "bundle-backup: bundle-backup.dest must be an absolute path (got $dest)."
	exit 0
	;;
esac
if [ ! -d "$dest" ]; then
	echo "bundle-backup: destination $dest does not exist (is the sync folder mounted?). Backups fail until it does."
	exit 0
fi
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
name=$(git config --get bundle-backup.name) || name=$(basename "$(git worktree list --porcelain | sed -n '1s/^worktree //p')")
statusf="$common/bundle-backup.status"
logf="$common/bundle-backup.log"
lock="$common/bundle-backup.lock"
bundle="$dest/$name.bundle"

log() { # log <event> [detail]
	printf '%s %s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" "$1" "${2:-}" >>"$logf" 2>/dev/null
}

# Wait up to 20 s for a backup run in progress (a commit made just before the
# session started) to finish, so its outcome is what gets judged. Only the
# lock counts: a leftover request file with no run holding the lock must not
# hold up every session start.
wait_idle() {
	for _ in $(seq 1 40); do
		[ -d "$lock" ] || return 0
		# A lock whose process is gone: the repair run takes it over.
		pid=$(cat "$lock/pid" 2>/dev/null) && ! kill -0 "$pid" 2>/dev/null && return 0
		sleep 0.5
	done
	return 1
}

# The same full check the backup run uses: git bundle verify reads only the
# header, so unpack every object into a throwaway repository.
full_check() {
	local check rc
	check=$(mktemp -d "${TMPDIR:-/tmp}/bundle-backup-check.XXXXXX") || return 1
	(
		unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
		git init -q --bare "$check/r" >/dev/null 2>&1 &&
			git -C "$check/r" bundle unbundle "$1" >/dev/null 2>&1
	)
	rc=$?
	rm -rf "$check"
	return $rc
}

# diagnose: print why the backup needs a repair, or nothing when it is sound.
diagnose() {
	local status last latest
	if ! status=$(cat "$statusf" 2>/dev/null); then
		echo "no backup has run yet"
		return
	fi
	case "$status" in
	error*)
		echo "the last backup failed: ${status#error }"
		return
		;;
	writing*)
		echo "the last backup was interrupted while writing"
		return
		;;
	esac
	set -- $status
	last=${3:-0}
	latest=$(git for-each-ref --sort=-committerdate --count=1 --format='%(committerdate:unix)' 2>/dev/null)
	if [ -n "$latest" ] && [ "$last" -gt 0 ] 2>/dev/null && [ "$latest" -gt "$last" ]; then
		echo "the last backup ($2) is older than the latest commit"
		return
	fi
	if [ ! -f "$bundle" ]; then
		echo "$bundle is missing"
		return
	fi
	if ! full_check "$bundle"; then
		echo "$bundle is damaged"
	fi
}

wait_idle || log "check" "a backup run is still going after 20 s"
reason=$(diagnose)
[ -n "$reason" ] || exit 0

log repair "$reason"
hook=$(git rev-parse --path-format=absolute --git-path hooks/post-commit 2>/dev/null)
if [ ! -x "$hook" ]; then
	log "repair failed" "no post-commit hook at $hook"
	echo "bundle-backup: the backup needs a repair ($reason), but it can't run because the post-commit hook isn't installed. cg sync --apply installs it and reports why not."
	exit 0
fi
# The run logs "start repair <this pid>", or "queued repair <this pid>" when a
# run in progress takes the request over, which tells whether it ran: the
# status alone can come out identical when two runs end in the same second.
tag="repair $$"
BUNDLE_BACKUP_FOREGROUND=1 BUNDLE_BACKUP_TRIGGER="$tag" "$hook" </dev/null >/dev/null 2>&1
wait_idle || :
after=$(cat "$statusf" 2>/dev/null)
if ! grep -qE " (start|queued) $tag\$" "$logf" 2>/dev/null; then
	log "repair failed" "no backup ran"
	echo "bundle-backup: the backup needs a repair ($reason), but no backup ran. The hook script may not be approved: cg sync --apply approves it and reports why not. Details: $logf"
	exit 0
fi
case "$after" in
ok*)
	if full_check "$bundle"; then
		log repaired "$reason"
		exit 0
	fi
	log "repair failed" "$bundle is still damaged after a backup"
	echo "bundle-backup: the backup needed a repair ($reason) and the repaired bundle still fails its check. Details: $logf"
	;;
*)
	log "repair failed" "$after"
	echo "bundle-backup: the backup needed a repair ($reason) and the automatic repair failed: ${after#* * * }. Details: $logf"
	;;
esac
exit 0
