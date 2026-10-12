---
title: "Obsidian Over a Consigliere Workspace — Gotchas"
category: tool-gotchas
tags: [obsidian, markdown, wikilinks, frontmatter, bases, ai-instructions]
---

# Obsidian Over a Consigliere Workspace — Gotchas

> Shipped by the [`obsidian`](https://github.com/mnemcik/cg-extensions/tree/main/obsidian) Consigliere extension. Edit the source there, not this copy — `cg extension update obsidian` overwrites it.

## When to load this note

Before writing wikilinks, tags, `.obsidian/` config or a `.base` file in a workspace that is opened as an Obsidian vault. Most of a workspace written for GitHub works in Obsidian unchanged; the points below are the ones that break silently.

Points marked *(observed)* were seen in a real vault but are not stated in the [official docs](https://github.com/obsidianmd/obsidian-help); re-check them if Obsidian's behaviour seems to differ.

## Links

- **Wikilink paths start at the vault root** ([links docs](https://obsidian.md/help/links)). `[[../notes/foo]]` renders as an unresolved link *(observed)*. Write `[[notes/foo]]`. When converting an existing relative wikilink, resolve the target against the file's own folder and re-express it from the root. Don't just strip the `../`: in `insights/2026-07-14/x.md`, `[[../2026-06-25/y]]` must become `[[insights/2026-06-25/y]]`.
- **Markdown links are unaffected.** `[foo](../areas/x.md)` resolves relative to the file, as on GitHub, so prefer markdown links in files that are also read on a git host.
- **Links to a folder don't resolve** *(observed)*. `[slug](slug/)` works on GitHub but not in Obsidian, which links to notes. Write `[slug](slug/README.md)`; it works in both.

## Tags and properties

- **Tag values can't contain a dot.** Allowed are letters, digits, `_`, `-` and `/`. `chat.postmessage` is not a tag. Fix it in the source frontmatter.
- **Date properties plus Daily notes create empty files.** A frontmatter value that parses as a date (`created: 2026-09-02`) is clickable in the Properties panel, and with the Daily notes core plugin enabled a click creates that day's note, an empty file. If you don't keep a journal, turn Daily notes off (Settings → Core plugins). Keep the date properties; Bases sorts on them.

## Vault config (`.obsidian/`)

- The extension seeds `app.json` (new notes in `notes/`, pasted attachments in `attachments/`, links updated on rename, `templates/` kept out of search) and `templates.json` (the `templates/` folder for the Templates plugin).
- Obsidian rewrites `app.json` itself whenever a setting changes, and writes it without a trailing newline *(observed)*. Commit its own output rather than reformatting it, or the file stays dirty.
- `workspace.json` holds per-machine UI layout; `workspace-mobile.json` and `cache` behave the same way *(observed)*. The extension gitignores all three. The rest of `.obsidian/` is shared config and is tracked.
- Hidden folders (`.git/`, `.claude/`, `.cg/`) are skipped by Obsidian with no configuration *(observed)*.

## Bases (`.base` files)

- **Reference note properties bare** (`status`) or with `note.` (`note.status`) in filters and formulas, and bare in a view's `order` *(observed)*. Prefer these to `file.properties.status`.
- **Display names need the prefix.** Under the top-level `properties:` key, write `note.status:` with its `displayName`. A bare `status:` key is ignored and the column shows the raw property name *(observed, Obsidian 1.13.7)*, although the [syntax docs](https://github.com/obsidianmd/obsidian-help/blob/master/en/Bases/Bases%20syntax.md) example shows a bare `status:` key.
- **Select project READMEs by path:** `file.path.endsWith("/README.md")`. It is unambiguous, since every project has a file of that name. The [functions reference](https://github.com/obsidianmd/obsidian-help/blob/master/en/Bases/Functions.md) lists `file.name` (the file's name), `file.basename` (without the extension), `file.ext` and `file.folder` if you need them.
- **An invalid expression fails silently**: the view is just empty, with no error.
- **Obsidian rewrites a `.base` file into its own serialisation** *(observed)*. Comments are stripped, quoting is normalised and per-viewer state such as `columnSize` is written back when you resize a column. A file already in that form, with no comments, was left unchanged on opening *(observed, Obsidian 1.13.7)*. Keep any explanation of a filter outside the file, and commit Obsidian's serialisation.

## Navigating many `README.md` files

Every project has a `README.md`, `todo.md`, `log.md` and `decisions.md`. That is less of a problem than it looks: the quick switcher shows the folder path when file names collide and matches on it, so typing the project slug finds the file *(observed)*. Graph view shows file names only, so it is the one place the duplicates hurt. The community plugin [Front Matter Title](https://github.com/snezhig/obsidian-front-matter-title) can show each file's `title:` frontmatter instead; it is optional.

## Sourcing

For Obsidian's config files and the Bases expression language, read the raw markdown in [`obsidianmd/obsidian-help`](https://github.com/obsidianmd/obsidian-help), which has exact worked examples, and check its history: the file-field list was added to the functions reference only in late 2025. Summaries and unofficial wikis have been wrong about these fields.
