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

# Wait up to BUNDLE_BACKUP_WAIT seconds (default 20) for a backup run in
# progress (a commit made just before the session started) to finish, so its
# outcome is what gets judged. Only the lock counts: a leftover request file
# with no run holding the lock must not hold up every session start.
wait_s=${BUNDLE_BACKUP_WAIT:-20}
case "$wait_s" in
'' | *[!0-9]* | 0) wait_s=20 ;;
esac
# idle: no run holds the lock. A lock whose process is gone, or that is over
# 6 hours old (a hung run, or a dead one whose pid was reused), counts as
# idle too: the repair run takes it over, as any backup run would.
idle() {
	[ -d "$lock" ] || return 0
	[ -n "$(find "$lock" -maxdepth 0 -mmin +360 2>/dev/null)" ] && return 0
	pid=$(cat "$lock/pid" 2>/dev/null) && ! kill -0 "$pid" 2>/dev/null && return 0
	return 1
}
wait_idle() {
	for _ in $(seq 1 $((wait_s * 2))); do
		idle && return 0
		sleep 0.5
	done
	idle
}

# The same full check the backup run uses: git bundle verify reads only the
# header, so unpack every object into a throwaway repository.
full_check() {
	local check rc
	check=$(mktemp -d "${TMPDIR:-/tmp}/bundle-backup-check.XXXXXX") || return 1
	(
		unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
		# --git-dir, not discovery: safe.bareRepository=explicit refuses a
		# bare repository found by discovery.
		git init -q --bare "$check/r" >/dev/null 2>&1 &&
			git --git-dir="$check/r" bundle unbundle "$1" >/dev/null 2>&1
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

# Keep the log bounded when no backup run trims it.
if [ ! -d "$lock" ] && [ -f "$logf" ] && [ "$(wc -l <"$logf")" -gt 2000 ]; then
	tail -n 1000 "$logf" >"$logf.$$" && mv -f "$logf.$$" "$logf"
fi

# A run still going after the wait records its own outcome; judging it now
# would read a half-written bundle. The next session start looks again.
if ! wait_idle; then
	log "check" "a backup run is still going after ${wait_s} s; left to it"
	exit 0
fi
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
tag="repair $$-$(date +%s)"
BUNDLE_BACKUP_FOREGROUND=1 BUNDLE_BACKUP_TRIGGER="$tag" "$hook" </dev/null >/dev/null 2>&1
if ! wait_idle; then
	log "check" "the repair is still going after ${wait_s} s; left to it"
	exit 0
fi
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
writing*)
	log "repair failed" "the repair run was interrupted while writing"
	echo "bundle-backup: the backup needed a repair ($reason) and the repair run was interrupted while writing. Details: $logf"
	;;
*)
	log "repair failed" "$after"
	echo "bundle-backup: the backup needed a repair ($reason) and the automatic repair failed: ${after#* * * }. Details: $logf"
	;;
esac
exit 0
