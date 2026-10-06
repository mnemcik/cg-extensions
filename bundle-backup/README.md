# bundle-backup

A Consigliere extension that backs up the workspace as a `git bundle` after every commit, merge or rewrite. The bundle goes to a folder you choose, for example a synced company drive, so no git remote is needed.

## Problem

A workspace that should not live on a git host still needs an off-machine copy. A synced folder is the obvious place, but a git repository inside a sync client's folder is easily corrupted when the client syncs files mid-write. A bundle is a single file that holds the whole repository, so it's a safe thing to sync.

## Mechanism

The extension contributes one script as a `post-commit`, `post-merge` and `post-rewrite` git hook, through cg's `git-hooks` contribution point (cg 1.25 or later). Together these cover direct commits, `cg worktree land` in a remote-free workspace (a fast-forward in the main checkout fires `post-merge`), amends and rebases. Each time it runs, the script:

1. Returns at once and works in the background, so commits never wait. The background job leaves the hook's checkout and environment, so removing a session worktree right after landing doesn't break it.
2. Takes a lock in the git dir. A run that finds the lock held asks the holder to go once more, so a burst of commits from parallel sessions produces one or two bundles, not one per commit. A lock whose process is gone is taken over.
3. Runs `git bundle create --all` to a temp file in the destination, checks it with `git bundle verify`, then renames it over `<name>.bundle`.
4. Copies the result to `daily/<name>-YYYY-MM-DD.bundle`, keeping the last state of each day, and deletes daily copies older than `keepDays`.
5. Records `ok` or `error` with a timestamp in `<git-dir>/bundle-backup.status`.

A `SessionStart` check reports, as a session message, when:

- no destination is set
- the destination doesn't exist (for example, the sync folder isn't mounted)
- no backup has run yet
- the last backup failed
- the last good backup is over an hour older than the latest commit

When everything is fine it stays silent.

The extension also adds a CLAUDE.md section that explains the backup and how to restore from it.

## Configuration

Settings are per repository, in git config, so they stay on the machine and out of the workspace:

```sh
git config bundle-backup.dest "$HOME/Library/CloudStorage/GoogleDrive-<account>/My Drive/workspace-backup"
git config bundle-backup.name my-workspace   # optional; default: the main worktree's directory name
git config bundle-backup.keepDays 30         # optional; daily copies to keep
```

Until `bundle-backup.dest` is set, the script does nothing. The destination must already exist. The script never creates it, so a sync folder that isn't mounted shows up as a failed backup instead of a local copy that never syncs.

## Restore

```sh
git bundle verify my-workspace.bundle
git clone --mirror my-workspace.bundle my-workspace.git   # every branch, full history
git clone my-workspace.git my-workspace
```

A plain `git clone my-workspace.bundle` checks out only the bundle's `HEAD` branch. With `--mirror`, the intermediate `my-workspace.git` has every branch. The working clone made from it has `main` locally and the other branches as `origin/*`; `git switch <branch>` creates a local one.

## What it does not cover

Uncommitted changes, git-ignored files, older stashes and local git config (`.git/config`, hooks) aren't in the bundle. The latest stash is (`refs/stash`); earlier stash entries live only in the reflog.

## Tests

`tests/run.sh` runs the script against throwaway repositories. It covers:

- an unset destination
- a restore that checks every branch and commit came back
- daily copies, and pruning of old ones
- a burst of concurrent runs
- a stale lock left by a dead process
- an unwritable destination
- commits from a linked worktree
- every message the `SessionStart` check can print
