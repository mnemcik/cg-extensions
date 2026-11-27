# shopping

A Consigliere extension that gives a workspace one shared shopping list. Any project can add items from any session, and open items group by supplier, so one order covers what every project needs from that supplier.

## Problem

When each project keeps its own buy list (usually a section of its `todo.md`), nothing shows across projects what is waiting to be ordered, or from where. Orders go out one project at a time and each pays its own shipping and minimum-order costs, items another project needs from the same supplier get missed, and "needed / ordered / received" is tracked inconsistently.

## Mechanism

Each item is one markdown file, `shopping/<id>.md` at the root of the work tree ([where](#where-the-items-go)), with its fields in YAML frontmatter (`title`, `status`, `supplier`, `qty`, `project`, `part`, `mpn`, `link`, `price`, `needed_by`, and the dates and order number `cg shop` records). The id is `<date>-<slug-of-title>-<6 random hex digits>`, for example `2026-11-13-esp32-c6-module-3fa91c`; any unique prefix works on the command line.

- **No conflicts between parallel sessions.** A new item is a new file with a random part in its name, and a status change edits only that item's file. Two sessions adding items in separate worktrees, even the same item on the same day, land without conflicts (the test suite checks this). A single shared list file would conflict as soon as two sessions append to it.
- **In git, and plain text.** Items are committed like the rest of the workspace, so they travel with it, show in history, and are readable by any tool (Obsidian, an editor, `grep`).
- **Views are computed, not stored.** `cg shop list` reads the files and groups them, so there is no index file to keep in sync.
- **Status:** `needed` → `ordered` → `received`, or `cancelled`. Closed items stay as files, keeping the record of which project needed what.

The extension contributes:

| Contribution | What |
|---|---|
| `commands` | `cg shop`, `cg shop add`, `list`, `order`, `receive`, `cancel`, `show` (`bin/cg-shop`, a bash script) |
| `claude-md-sections` | A short rule: purchases go in the shared list, never in a project's `todo.md` |
| `notes` | `notes/shopping-list-workflow.md` — fields, rules, commands, putting an order together |
| `templates` | `templates/shopping-item.md` — the item format, for writing one by hand |

## Usage

```sh
cg shop add "ESP32-C6 module" --supplier lcsc --qty 10 --project weather-station --part C5366877
cg shop list                       # open items, grouped by supplier
cg shop list --by project
cg shop order lcsc --ref LC261113  # every needed lcsc item → ordered
cg shop receive --ref LC261113
cg shop cancel <id>
cg shop help
```

`cg shop` writes the files but does not commit them; commit them with the session's work.

### Where the items go

`cg shop` uses the `shopping/` folder at the top level of the git work tree of the first of these that applies (so a workspace in a subfolder of its repo keeps the repo's one list):

1. `CG_SHOP_DIR`, when set: that folder itself, used as given (an override, used by the tests).
2. The session's worktree (`CG_SESSION_WORKTREE`, cg 2.0+). cg sets it when it serves `cg shop` from the session's workspace for a directory outside the workspace, so items from a session working in another repo land in the session's worktree, not the main checkout.
3. The workspace that served the command (`CG_EXTENSION_WORKSPACE`, cg 2.0+), when the current directory is inside it (a git repo nested in the workspace still uses the workspace's list).
4. Outside that workspace with no session worktree: `list` and `show` read the workspace's list, and `add`, `order`, `receive` and `cancel` refuse, naming `cg worktree create <slug>` and `cg session set-context --worktree <path>`.
5. Otherwise (cg 1.x, or `bin/cg-shop` run directly): the current git work tree.

## Install

```sh
cg extension install cg/shopping
```

## Requirements and limits

- **cg 2.0 or later** (manifest v2): cg 1.x refuses to install this version. `shopping/bin/cg-shop` can still be run directly.
- bash 3.2 or later, git, and POSIX `awk`, `sed`, `sort`. Tested on macOS (bash 3.2) and Linux (bash 5).
- Windows: cg runs the command's binary directly, which needs a shell that can run a bash script; not tested.
- Not in 0.1: prices and order totals, supplier minimum-order or free-shipping thresholds, warnings for open items of a finished project.

## Tests

```sh
shopping/tests/run.sh
```
