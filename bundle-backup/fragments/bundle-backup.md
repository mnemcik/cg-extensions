## Workspace Backup (bundle-backup)

This workspace is backed up as a `git bundle` after every commit, merge or rewrite, into the folder set with `git config bundle-backup.dest <folder>`: `<name>.bundle` is the latest state (every branch, full history) and `daily/<name>-YYYY-MM-DD.bundle` keeps the last state of each day. It covers committed work only — uncommitted changes, git-ignored files and `.git/config` are not in it. A SessionStart check reports a missing destination or a failed backup; act on it rather than ignore it.

**Restore:** `git clone --mirror <folder>/<name>.bundle <repo>.git`, then `git clone <repo>.git <workspace>` — a plain `git clone` of the bundle checks out only its HEAD branch. `git bundle verify <file>` checks a bundle first.
