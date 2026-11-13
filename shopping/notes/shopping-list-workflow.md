# Shopping List Workflow

The workspace keeps **one shared shopping list** for every project, managed with `cg shop` (from the `shopping` extension). It exists so that purchases from several projects go out as one order per supplier, nothing a project needs gets missed, and every item has a clear status.

## Where items live

Each item is a markdown file, `shopping/<id>.md` at the root of the work tree, with its fields in frontmatter:

| Field | Meaning |
|---|---|
| `title` | What to buy |
| `status` | `needed` → `ordered` → `received`, or `cancelled` |
| `supplier` | Supplier slug (`LCSC` is stored as `lcsc`) |
| `qty` | Quantity, a whole number |
| `project` | Slug of the project that needs it |
| `part`, `mpn` | Supplier part number, manufacturer part number |
| `link`, `price`, `needed_by` | Optional |
| `added`, `ordered`, `received`, `order_ref` | Set by `cg shop` |

The id is `<added-date>-<slug-of-title>-<6 random hex digits>`. The random part is always there, so two sessions adding the same item on the same day still create different files, and lands never conflict. Item files are workspace content like any other — **stage and commit them by name** with the session's work, or they never reach `main`.

## Rules

- **Purchases live only here.** Don't keep a buy list in a project's `todo.md`. If the project's next action depends on the parts, write one line such as *"waiting for parts — `cg shop list --project <slug>`"*, not the items.
- **Always set `--project`** when the item is for a project, and use the project's folder slug.
- **Reuse supplier names.** Run `cg shop list --all` and use the spelling already there; `digikey` and `digi-key` are two suppliers to the tool.
- **Prefer the supplier's part number** (`--part`) when there is one; it is what an order form wants.
- Received and cancelled items stay as files: they are the record of which project needed what. Don't delete them.

## Commands

```sh
cg shop add "ESP32-C6 module" --supplier lcsc --qty 10 --project weather-station --part C5366877
cg shop list                       # open items (needed + ordered), grouped by supplier
cg shop list --by project          # the same, grouped by project
cg shop list --project lamp        # one project's purchases
cg shop list --all                 # include received and cancelled
cg shop order lcsc --ref LC261113  # every needed lcsc item → ordered, with the order number
cg shop order lcsc <id> <id>       # only these items
cg shop receive --ref LC261113     # the whole order arrived
cg shop receive <id>               # one item arrived
cg shop cancel <id>
cg shop show <id>
```

Ids can be shortened to any unique prefix. `cg shop list --tsv` gives every field as tab-separated rows for scripting.

## Putting an order together

When the user wants to order from a supplier, or asks what to buy:

1. `cg shop list --supplier <s>` and show the needed items, with the project each is for.
2. Point out needed items from the **same supplier in other projects**, since adding them is the whole point of the shared list.
3. After the user places the order, `cg shop order <s> --ref <order no>` (only the ids they actually ordered, if not all).
4. Commit the changed item files.
