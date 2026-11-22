# Changelog

## 0.2.0

- **Added:** with cg 2.0+, `cg shop` works from a directory outside the workspace. It picks its root in this order: `CG_SHOP_DIR` (the explicit override, unchanged); the session's worktree (`CG_SESSION_WORKTREE`); the workspace that served the command (`CG_EXTENSION_WORKSPACE`) when the current directory is inside it; the current git work tree (cg 1.x, or `cg-shop` run directly).
- **Added:** run from outside the workspace in a session with no worktree, `cg shop add | order | receive | cancel` refuse and name the fix (`cg worktree create <slug>`, or `cg session set-context --worktree <path>`), so items never land in the workspace's main checkout from somewhere else. `cg shop list | show` read the workspace's list there.
- With cg 1.x none of these variables is set, and `cg shop` behaves as in 0.1.0.

## 0.1.0

- **Added:** `cg shop add | list | order | receive | cancel | show`. One file per item under `shopping/`, grouped views by supplier or project, whole-supplier ordering with an order number, receiving by order number.
- **Added:** ids are `<date>-<slug>-<6 hex>`, so parallel sessions adding the same item never conflict; CRLF files read and update; ids are checked, so a path can't escape `shopping/`.
- **Added:** CLAUDE.md rule, workflow note and item template.
