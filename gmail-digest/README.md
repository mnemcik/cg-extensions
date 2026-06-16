# gmail-digest

A [Consigliere](https://github.com/mnemcik/consigliere) extension that turns
**"check / digest X updates"** into a structured digest of unread Gmail for a
label — with per-target tracking so each run picks up where the last left off.

The mechanism is generic (anyone with Gmail access can use it); the list of
labels you monitor stays in your workspace.

## Install

```sh
cg extension install cg/gmail-digest   # fully-qualified: <registry>/<extension>, requires cg v1.6.0+
# or, without the registry (this extension is a subdir of the monorepo):
cg extension install https://github.com/mnemcik/cg-extensions --path gmail-digest
```

Remove cleanly with `cg extension remove gmail-digest`; update with
`cg extension update gmail-digest`.

## Prerequisite

A **Gmail MCP** (or equivalent Gmail access) configured in your client,
exposing thread search and read. The extension supplies the trigger rule and
workflow; it does not configure mail access.

## What it contributes

| Contribution | What lands |
|--------------|-----------|
| `claude-md-sections` → `gmail-digest` | A trigger rule in your `CLAUDE.md` (under an `ext:gmail-digest:section` marker): "check/digest X updates" → run the digest workflow, skip project identification, keep the worktree gate. |
| `notes` → `notes/gmail-digest-workflow.md` | The digest process: per-target file, `after:<epoch>` sync, the `label:`-name-not-ID gotcha, output structure, history tracking. |
| `templates` → `templates/gmail-digest-target.md` | A target-file skeleton (label name + ID, output slug, domain context, digest-history table). |

## Defining targets

Copy the template once per label you want to monitor:

```sh
mkdir -p notes/gmail-digest-targets
cp templates/gmail-digest-target.md notes/gmail-digest-targets/<target>.md
# then fill in the Gmail label, slug, and domain context
```

The workflow reads `notes/gmail-digest-targets/` to find what you monitor.

Content-only — no binary. Pairs well with the marketplace `gmail-digest` skill,
which runs the analysis pass; this extension supplies the workspace trigger rule
and workflow conventions.

## Authoring / contributing

See the Consigliere [extension authoring guide](https://github.com/mnemcik/consigliere/blob/main/EXTENSIONS.md).
The manifest is `cg-extension.json`; CI validates it against the
[canonical schema](https://github.com/mnemcik/cg-extensions-registry/blob/main/schema/cg-extension.schema.json).

## License

MIT — see the [LICENSE](../LICENSE) at the monorepo root.
