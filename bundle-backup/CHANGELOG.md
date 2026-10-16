# Changelog

## 0.1.2

- **Fixed:** with the destination in Google Drive for desktop on macOS, earlier versions of `<name>.bundle` piled up in the macOS Trash, about 10 MB each, most runs. The backup renamed a temp file over the bundle, which leaves a new file in place of the old one, and Drive moved the replaced file to the Trash. It now builds and verifies the bundle in the git dir and writes it into the existing files in place, so they keep their identity and Drive records a new version instead. Each copy is checked against the verified bundle. The write into the destination is no longer atomic: a run cut short mid-write leaves a broken latest bundle until the next commit, while earlier daily copies stay intact.

## 0.1.1

- **Fixed:** the restore instructions in the README and the CLAUDE.md section said to run `git bundle verify` on the file before cloning. Outside a repository that fails with "need a repository to verify a bundle". They now verify inside the mirror clone. Found in the first real restore drill.

## 0.1.0

- **Added:** back up the workspace as a `git bundle --all` to the folder in `git config bundle-backup.dest`. It runs as a `post-commit`, `post-merge` and `post-rewrite` git hook and works in the background. A lock with rerun-once coalesces bursts of commits. Each bundle is verified before it replaces `<name>.bundle`, a daily copy is kept under `daily/` and pruned after `keepDays` (default 30), and every run records its outcome in `<git-dir>/bundle-backup.status`.
- **Added:** a `SessionStart` check. It reports a missing destination setting, a destination folder that doesn't exist, no backup yet, a failed last backup, or a backup over an hour older than the latest commit.
- **Added:** a CLAUDE.md section that explains the backup and the `git clone --mirror` restore.
