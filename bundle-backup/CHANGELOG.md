# Changelog

## 0.1.0

- **Added:** back up the workspace as a `git bundle --all` to the folder in `git config bundle-backup.dest`. It runs as a `post-commit`, `post-merge` and `post-rewrite` git hook and works in the background. A lock with rerun-once coalesces bursts of commits. Each bundle is verified before it replaces `<name>.bundle`, a daily copy is kept under `daily/` and pruned after `keepDays` (default 30), and every run records its outcome in `<git-dir>/bundle-backup.status`.
- **Added:** a `SessionStart` check that reports a missing destination, a destination that doesn't exist, or a failed last backup.
- **Added:** a CLAUDE.md section that explains the backup and the `git clone --mirror` restore.
