# shopping

A Consigliere extension that gives a workspace one shared shopping list. Any project can add items from any session, and open items group by supplier, so one order covers what every project needs from that supplier.

## Problem

When each project keeps its own buy list (usually a section of its `todo.md`), nothing shows across projects what is waiting to be ordered, or from where. Orders go out one project at a time and each pays its own shipping and minimum-order costs, items another project needs from the same supplier get missed, and "needed / ordered / received" is tracked inconsistently.

## Mechanism

Each item is one markdown file, `shopping/<id>.md` at the root of the work tree, with its fields in YAML frontmatter (`title`, `status`, `supplier`, `qty`, `project`, `part`, `mpn`, `link`, `price`, `needed_by`, and the dates and order number `cg shop` records). The id is `<date>-<slug-of-title>`.

- **No conflicts between parallel sessions.** A new item is a new file, and a status change edits only that item's file. Two sessions adding items in separate worktrees land without conflicts (the test suite checks this). A single shared list file would conflict as soon as two sessions append to it.
- **In git, and plain text.** Items are committed like the rest of the workspace, so they travel with it, show in history, and are readable by any tool (Obsidian, an editor, `grep`).
- **Views are computed, not stored.** `cg shop list` reads the files and groups them, so there is no index file to keep in sync.
- **Status:** `needed` → `ordered` → `received`, or `cancelled`. Closed items stay as files, keeping the record of which project needed what.

The extension contributes:

| Contribution | What |
|---|---|
| `subcommands` | `cg shop` (`bin/cg-shop`, a bash script) |
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

## Install

```sh
cg extension install cg/shopping
```

## Requirements and limits

- **cg later than 1.30.1.** Up to 1.30.1, cg looks for a co-located extension's subcommand at the repo root rather than under its subdir, so `cg shop` fails with `unknown command "shop"` (fixed in `mnemcik/consigliere`, `fix/subcommand-subdir`). Until then, `shopping/bin/cg-shop` can be run directly.
- bash 3.2 or later, git, and POSIX `awk`, `sed`, `sort`. Tested on macOS (bash 3.2) and Linux (bash 5).
- Windows: cg runs the subcommand directly, which needs a shell that can run a bash script; not tested.
- Not in 0.1: prices and order totals, supplier minimum-order or free-shipping thresholds, warnings for open items of a finished project.

## Tests

```sh
shopping/tests/run.sh
```
