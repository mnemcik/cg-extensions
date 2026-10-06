#!/usr/bin/env bash
# bundle-backup SessionStart check: say so when backups are not configured,
# when the destination is missing (e.g. the sync folder is not mounted), when
# no backup has run yet, when the last backup failed, or when the last good
# backup is older than the latest commit by over an hour. Silent when all is
# well.
dest=$(git config --get bundle-backup.dest 2>/dev/null) || dest=
if [ -z "$dest" ]; then
	echo "bundle-backup: no destination set, so this workspace is not being backed up. Set one with: git config bundle-backup.dest <folder>"
	exit 0
fi
if [ ! -d "$dest" ]; then
	echo "bundle-backup: destination $dest does not exist (is the sync folder mounted?). Backups fail until it does."
	exit 0
fi
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
if ! status=$(cat "$common/bundle-backup.status" 2>/dev/null); then
	echo "bundle-backup: no backup has run yet. One runs after the next commit; if none appears, check that cg installed the git-hook dispatcher (cg sync --apply reports why not)."
	exit 0
fi
case "$status" in
error*)
	echo "bundle-backup: the last backup failed — ${status#error }"
	exit 0
	;;
esac
set -- $status
last=${3:-0}
latest=$(git for-each-ref --sort=-committerdate --count=1 --format='%(committerdate:unix)' 2>/dev/null)
if [ -n "$latest" ] && [ "$last" -gt 0 ] 2>/dev/null && [ "$latest" -gt $((last + 3600)) ]; then
	echo "bundle-backup: the last successful backup ($2) is over an hour older than the latest commit; backups may not be running."
fi
exit 0
