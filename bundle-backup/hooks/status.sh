#!/usr/bin/env bash
# bundle-backup SessionStart check: say so when backups are not configured,
# when the destination is missing (e.g. the sync folder is not mounted), or
# when the last backup failed. Silent when all is well.
dest=$(git config --get bundle-backup.dest 2>/dev/null) || dest=
if [ -z "$dest" ]; then
	echo "bundle-backup: no destination set, so this workspace is not being backed up. Set one with: git config bundle-backup.dest <folder>"
	exit 0
fi
if [ ! -d "$dest" ]; then
	echo "bundle-backup: destination $dest does not exist (is the sync folder mounted?). Backups will fail until it does."
	exit 0
fi
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
status=$(cat "$common/bundle-backup.status" 2>/dev/null) || exit 0
case "$status" in
error*) echo "bundle-backup: the last backup failed — ${status#error }" ;;
esac
exit 0
