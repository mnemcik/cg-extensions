# bundle-backup

A Consigliere extension that backs up the workspace as a `git bundle` after every commit, merge or rewrite. The bundle goes to a folder you choose, for example a synced company drive, so no git remote is needed.

## Problem

A workspace that should not live on a git host still needs an off-machine copy. A synced folder is the obvious place, but a git repository inside a sync client's folder is easily corrupted when the client syncs files mid-write. A bundle is a single file that holds the whole repository, so it's a safe thing to sync.

## Mechanism

The extension contributes one script as a `post-commit`, `post-merge` and `post-rewrite` git hook, through cg's `git-hooks` contribution point (cg 1.25 or later). Together these cover direct commits, `cg worktree land` in a remote-free workspace (a fast-forward in the main checkout fires `post-merge`), amends and rebases. Each time it runs, the script:

1. Returns at once and works in the background, so commits never wait. The background job leaves the hook's checkout and environment, so removing a session worktree right after landing doesn't break it.
2. Takes a lock in the git dir. A run that finds the lock held asks the holder to go once more, so a burst of commits from parallel sessions produces one or two bundles, not one per commit. A lock whose process is gone is taken over.
3. Runs `git bundle create --all` to a temp file in the git dir and checks it by unpacking every object into a throwaway repository. `git bundle verify` isn't enough: it reads only the header, and passes a truncated or damaged bundle.
4. Records `writing` in the status, writes the bundle into `<name>.bundle` and, unless daily copies are off, `daily/<name>-YYYY-MM-DD.bundle` in place, checks each copy against the temp file, and, unless daily copies are off, deletes daily copies older than `keepDays`. The daily copy keeps the last state of each day. The files are written in place, not replaced by a rename, so they keep their identity: under Google Drive for desktop on macOS, a rename over a file sends the file it replaced to the macOS Trash. The write is not atomic, which is why the status says `writing` until it's done. If the refs in the new bundle no longer match the live ones (a command that fires no hook moved a branch while the bundle was made), the run goes once more, with at most two extra passes.
5. Records `ok` or `error` with a timestamp in `<git-dir>/bundle-backup.status`, and appends every step (what started the run, writing, ok, error, a queued or killed run) to `<git-dir>/bundle-backup.log`. The log stays on the machine, is never synced, and is trimmed to its last 1000 lines once it passes 2000.

### Self-repair at session start

A `SessionStart` check repairs the backup without involving the user when one of these is true:

- no backup has run yet
- the last backup failed, or was interrupted while writing (the status still says `writing`)
- the refs in the destination bundle differ from the live ones: every ref, `HEAD` and each linked worktree's `HEAD`, read from the common git dir. That covers a new commit, and also changes that bring no newer commit date: a fast-forward land whose backup didn't run, a deleted or reset branch, a new tag or stash. It also covers a file in the destination that isn't the one written, such as a version restored by the sync client
- `<name>.bundle` is missing from the destination, or fails the same full check

It first waits up to 20 seconds for a backup already in progress. Then it runs the repository's `post-commit` hook in the foreground, the same hook a commit runs, so cg's approval of the script still applies. Any other `post-commit` scripts run too, as they would on a commit. Afterwards it checks the bundle again. Each repair and its outcome is logged.

It shows a session message only when the user has to act:

- no destination is set, or it isn't an absolute path
- the destination doesn't exist (for example, the sync folder isn't mounted)
- the `post-commit` hook isn't installed, or no backup ran (for example, the script isn't approved)
- the repair failed; the message gives the reason and the log's path

When everything is fine, or a repair succeeded, it stays silent.

The extension also adds a CLAUDE.md section that explains the backup and how to restore from it.

## Configuration

Settings are per repository, in git config, so they stay on the machine and out of the workspace:

```sh
git config bundle-backup.dest "$HOME/Library/CloudStorage/GoogleDrive-<account>/My Drive/workspace-backup"
git config bundle-backup.name my-workspace   # optional; default: the main worktree's directory name
git config bundle-backup.keepDays 30         # optional; daily copies to keep
git config bundle-backup.daily false         # optional; keep no daily copies (default true)
```

**Daily copies.** Every bundle holds every branch with its full history, so daily copies add no history. They keep earlier *ref* states: a branch deleted before it was merged, or commits a rewrite dropped, once that loss has reached the latest bundle. With `bundle-backup.daily false`, only `<name>.bundle` is written, and nothing in `daily/` is created, written or deleted. Git's false values turn daily copies off: `false`, `no`, `off`, `0`, or an empty value. An unset value, a true value, or one git can't read as a boolean keeps them on. The setting is read on every backup pass, so it applies from the next commit even while a backup is running. Copies already there stay until you remove them. Turning copies back on restarts the prune, and its first run deletes every leftover copy older than `keepDays` at once, so remove them first.

With daily copies off, nothing in the destination falls back to an earlier state. The write into `<name>.bundle` isn't atomic, so a run cut short while writing leaves a broken latest bundle. Until the next successful run (the next commit, or the repair at the next session start), the only earlier state is whatever versions the sync client keeps of that file. With daily copies on, the copies of earlier days stay intact. The repository itself isn't affected either way.

Under Google Drive for desktop on macOS, every daily copy pruned after `keepDays` also lands in the macOS Trash (and the Drive trash), about one a day once copies pass `keepDays`. Turn daily copies off to avoid it. Remove leftover copies through the Drive web UI rather than Finder or `rm`, which send them to the macOS Trash too.

Until `bundle-backup.dest` is set, the script does nothing. The destination must be an absolute path (`~` is expanded) and must already exist. The script never creates it, so a sync folder that isn't mounted shows up as a failed backup instead of a local copy that never syncs.

## Restore

```sh
git clone --mirror my-workspace.bundle my-workspace.git   # every branch, full history
git -C my-workspace.git fsck --full                       # optional: check every object
git clone my-workspace.git my-workspace
```

The mirror clone unpacks and checks every object, and fails on a damaged bundle. `git bundle verify` isn't a substitute: it reads only the header.

A plain `git clone my-workspace.bundle` checks out only the bundle's `HEAD` branch. With `--mirror`, the intermediate `my-workspace.git` has every branch. The working clone made from it has `main` locally and the other branches as `origin/*`; `git switch <branch>` creates a local one.

## What it does not cover

Uncommitted changes, git-ignored files, older stashes and local git config (`.git/config`, hooks) aren't in the bundle. The latest stash is (`refs/stash`); earlier stash entries live only in the reflog.

## Tests

`tests/run.sh` runs the script against throwaway repositories. It covers:

- an unset destination
- a restore that checks every branch and commit came back
- daily copies, and pruning of old ones
- daily copies off: the latest bundle written, nothing in `daily/` created, written or deleted; an unreadable value keeps copies on
- a burst of concurrent runs
- a stale lock left by a dead process
- an unwritable destination
- commits from a linked worktree
- the bundle and the daily copy rewritten in place (same file across runs)
- silent self-repair of a missing first backup, an interrupted write and a truncated bundle that `git bundle verify` passes
- ref changes without a newer commit date repaired: a new branch, a fast-forward of `main`, a deleted branch, a detached worktree's commit, an annotated tag
- a session in a linked worktree finds a current backup current, and a current backup isn't repaired again
- a repair that fails, a missing hook, and a hook that runs no backup, each reported
- a missing bundle repaired; a backup still running left alone, then repaired once it is gone
- `safe.bareRepository=explicit` in the global git config
- the log: trigger and steps recorded, trimmed past 2000 lines
- every message the `SessionStart` check prints, except that a repaired bundle still fails its check or that the repair run was itself interrupted
