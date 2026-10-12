# Changelog

## 0.1.1

- **Fixed:** the `active-projects.base` columns show their display names (Project, Status, Priority, Areas, Started). The `properties` keys now carry the `note.` prefix; Obsidian ignored the bare keys.
- **Changed:** the gotchas note covers the display-name prefix, and says Obsidian rewrites a `.base` file when the view changes rather than whenever it opens.

## 0.1.0

- **Added:** `.obsidian/app.json` (new-note and attachment folders, `alwaysUpdateLinks`, `templates/` excluded from search) and `.obsidian/templates.json`.
- **Added:** a `.gitignore` block for Obsidian's per-machine state: `workspace.json`, `workspace-mobile.json`, `cache` and `.trash/`.
- **Added:** `projects/active-projects.base`, a Bases table of projects not `done`.
- **Added:** the `notes/obsidian-vault-gotchas.md` note and a CLAUDE.md section that loads it before Claude writes wikilinks, tags, vault config or `.base` files.
