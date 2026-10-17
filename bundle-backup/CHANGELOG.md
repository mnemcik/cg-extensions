# Changelog

## 0.2.1

- **Fixed:** the `SessionStart` check judged whether the backup was current by commit dates, so ref changes without a newer commit date went unnoticed: a fast-forward land whose backup didn't run, a deleted or reset branch, a new tag. It now compares the refs in the destination bundle (`git bundle list-heads`) with the live refs, read from the common git dir so a session in a linked worktree compares the same list. A file in the destination that isn't the one written, such as a version restored by the sync client, is caught the same way.
- **Fixed:** when refs move while a bundle is being made, by a command that fires no hook, the run now goes once more (at most two extra passes), so the bundle ends up with the refs as they are.

## 0.2.0

- **Added:** the `SessionStart` check repairs the backup itself, without a session message. It does this when no backup has run yet, the last one failed or was interrupted while writing, the backup is older than the latest commit, or the bundle in the destination is missing or damaged. It runs the `post-commit` hook in the foreground, so cg's approval of the script still applies, and checks the bundle again afterwards. A message now appears only when the user has to act: no destination or a relative one, the destination missing, no hook or no backup run, or a repair that failed.
- **Added:** `<git-dir>/bundle-backup.log` records every run with what started it (the hook, a repair, a rerun), each step, and every repair and its outcome, for investigating problems later. It is trimmed to the last 1000 lines once it passes 2000.
- **Added:** the status says `writing` while the bundle is being written into the destination. A run killed mid-write therefore no longer leaves a stale `ok`.
- **Fixed:** the bundle is now checked by unpacking every object into a throwaway repository. `git bundle verify` reads only the header and passes a truncated or damaged bundle, so up to 0.1.2 the "verified" bundle was checked only by its header. The restore docs no longer suggest `git bundle verify` as a check.

## 0.1.2

- **Fixed:** with the destination in Google Drive for desktop on macOS, earlier versions of `<name>.bundle` piled up in the macOS Trash, about 10 MB each, most runs. The backup renamed a temp file over the bundle, which leaves a new file in place of the old one, and Drive moved the replaced file to the Trash. It now builds and verifies the bundle in the git dir and writes it into the existing files in place, so they keep their identity and Drive records a new version instead. Each copy is checked against the verified bundle. The write into the destination is no longer atomic: a run cut short mid-write leaves a broken latest bundle until the next commit, while earlier daily copies stay intact.

## 0.1.1

- **Fixed:** the restore instructions in the README and the CLAUDE.md section said to run `git bundle verify` on the file before cloning. Outside a repository that fails with "need a repository to verify a bundle". They now verify inside the mirror clone. Found in the first real restore drill.

## 0.1.0

- **Added:** back up the workspace as a `git bundle --all` to the folder in `git config bundle-backup.dest`. It runs as a `post-commit`, `post-merge` and `post-rewrite` git hook and works in the background. A lock with rerun-once coalesces bursts of commits. Each bundle is verified before it replaces `<name>.bundle`, a daily copy is kept under `daily/` and pruned after `keepDays` (default 30), and every run records its outcome in `<git-dir>/bundle-backup.status`.
- **Added:** a `SessionStart` check. It reports a missing destination setting, a destination folder that doesn't exist, no backup yet, a failed last backup, or a backup over an hour older than the latest commit.
- **Added:** a CLAUDE.md section that explains the backup and the `git clone --mirror` restore.
