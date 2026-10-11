# obsidian

A [Consigliere](https://github.com/mnemcik/consigliere) extension that makes a cg workspace work as an [Obsidian](https://obsidian.md) vault. cg itself stays independent of Obsidian; everything Obsidian-specific lives here.

## Problem

Opening Obsidian over a cg workspace works, but a few things go wrong until the vault is configured. New notes and pasted images land in the vault root. Per-machine UI state churns in git. Relative `../` wikilinks show as unresolved, because Obsidian resolves wikilink paths from the vault root. Tag values with a dot are not tags. And nothing tabulates projects by their frontmatter.

## Install

```sh
cg extension install cg/obsidian
# or, without the registry (this extension is a subdir of the monorepo):
cg extension install https://github.com/mnemcik/cg-extensions --path obsidian
```

Requires a cg release with the `gitignore` contribution point ([consigliere#160](https://github.com/mnemcik/consigliere/pull/160)). An older cg installs everything else but skips the `.gitignore` block. Item frontmatter (`title`, `status`, `priority`, `areas`, `created`), which the Bases view reads, is part of cg since 1.24; run `cg migrate` on an older workspace.

Then open the workspace folder in Obsidian as a vault.

Remove with `cg extension remove obsidian`; update with `cg extension update obsidian`.

## What it contributes

| Contribution | What lands |
|--------------|-----------|
| Template | `.obsidian/app.json`: new notes go to `notes/`, pasted attachments to `attachments/`, links are updated on rename, and `templates/` is kept out of search |
| Template | `.obsidian/templates.json`: the Templates core plugin reads `templates/` |
| Template | `projects/active-projects.base`: a Bases table of every project not `done`, with status, priority, areas and start date |
| `.gitignore` block | `.obsidian/workspace.json`, `.obsidian/workspace-mobile.json`, `.obsidian/cache` and `.trash/` |
| Note | `notes/obsidian-vault-gotchas.md`: what breaks silently (wikilink paths, folder links, tag characters, date properties, Bases expressions) |
| CLAUDE.md section | Tells Claude to load the note before writing wikilinks, tags, `.obsidian/` config or `.base` files |

The rest of `.obsidian/` is shared vault config and stays tracked.

## After installing

- **Bases:** if `projects/active-projects.base` doesn't open as a table, enable the Bases core plugin (Settings → Core plugins).
- **Daily notes:** if you don't keep a journal, turn the Daily notes core plugin off. With it on, clicking a date property such as `created:` creates an empty note for that day.
- **Optional:** the community plugin [Front Matter Title](https://github.com/snezhig/obsidian-front-matter-title) shows each file's `title:` instead of its file name, which helps in graph view where every project has a `README.md`.

The extension doesn't ship `core-plugins.json` or `graph.json`. Obsidian keeps all core plugins in one on/off map, so seeding it would override your own choices.

## Known limitations

These come from how cg copies template files ([consigliere#159](https://github.com/mnemcik/consigliere/issues/159)):

- **Install overwrites** an existing `.obsidian/app.json`, `.obsidian/templates.json` or `projects/active-projects.base` without asking. If you already use the folder as a vault, back up those files first and merge your settings back.
- **Remove deletes** those three files even if you changed them since installing. Obsidian rewrites `app.json` whenever you change a setting, so copy it first if you want to keep your settings.
