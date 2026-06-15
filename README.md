# cg-extensions

First-party [Consigliere](https://github.com/mnemcik/consigliere) extensions,
co-located in one repo. Each extension lives in its own subdirectory with its own
`cg-extension.json` manifest, README, and CHANGELOG, and is versioned
independently.

## Extensions

| Extension | What it does |
|-----------|--------------|
| [`1password`](1password/) | Makes 1Password the authoritative credential store — `op://` referencing, just-in-time `op` retrieval, item-creation requests, 1Password SSH-agent git auth. |
| [`spec-driven`](spec-driven/) | Spec-driven development workflow for greenfield software builds — PRD → layered specs → milestone implementation, gated to exclude brownfield/research/analysis/doc work. |
| [`voice`](voice/) | Drafts outbound messages (Slack, email, Jira, PR) in your own voice by loading a personal `VOICE.md` style guide; ships a skeleton, not anyone's content. |

## Install

By fully-qualified name (via the built-in `cg` [registry](https://github.com/mnemcik/cg-extensions-registry)):

```sh
cg extension install cg/1password
```

Installs are fully qualified (`<registry>/<extension>`) — the `cg` alias is the public catalogue. Requires `cg` v1.6.0+.

Or directly from this repo, pointing at the extension's subdir:

```sh
cg extension install https://github.com/mnemcik/cg-extensions --path 1password
```

Remove with `cg extension remove <name>`; update with `cg extension update <name>`.

## Layout

```text
cg-extensions/
  <name>/
    cg-extension.json      # manifest (schema v1)
    fragments/ notes/ …    # contribution payloads
    README.md  CHANGELOG.md
  LICENSE                  # repo-wide (MIT)
```

Each subdir is a complete, independently-installable extension. Because they
share one repo, `cg extension update` tracks the default branch and reads each
extension's version from its manifest's `version` field (a whole-repo git tag
can't identify one co-located extension's version) — so **bump the `version` in
the subdir's `cg-extension.json`** to publish a new version.

## Adding an extension

1. Create `<name>/cg-extension.json` plus its payload dirs (`fragments/`,
   `notes/`, `hooks/`, `templates/`, `bin/` as needed).
2. Add a per-extension `README.md` + `CHANGELOG.md`.
3. CI validates every `*/cg-extension.json` against the canonical schema on push.
4. Add an entry to the [registry](https://github.com/mnemcik/cg-extensions-registry)
   `index.json` with `path: "<name>"` to make it installable by name.

See the Consigliere
[extension authoring guide](https://github.com/mnemcik/consigliere/blob/main/EXTENSIONS.md)
for the manifest reference and contribution points.

## License

MIT — see [LICENSE](LICENSE).
