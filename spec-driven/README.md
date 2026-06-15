# spec-driven

A [Consigliere](https://github.com/mnemcik/consigliere) extension that adds a
**spec-driven development workflow** for greenfield software builds: PRD →
layered specs → milestone implementation, with AI-assisted spec authoring
followed by AI-driven implementation.

It teaches Claude to recognise when a *new* software project wants a PRD or spec
and to load the full methodology — four ground rules, three phases, a
spec-authoring step list, and prompt templates — without injecting any of that
into sessions that don't need it.

## Install

```sh
cg extension install cg/spec-driven   # fully-qualified: <registry>/<extension>, requires cg v1.6.0+
# or, without the registry (this extension is a subdir of the monorepo):
cg extension install https://github.com/mnemcik/cg-extensions --path spec-driven
```

Remove cleanly with `cg extension remove spec-driven`; update with
`cg extension update spec-driven`.

## What it contributes

| Contribution | What lands |
|--------------|-----------|
| `claude-md-sections` → `spec-driven-development` | A pointer-style trigger block in your `CLAUDE.md` (under an `ext:spec-driven:section` marker) that fires only for greenfield software builds wanting a PRD/spec — and explicitly excludes brownfield/existing-codebase, research, analysis, event, and documentation work. |
| `notes` → `notes/spec-driven-development.md` | The full methodology body: four ground rules, three phases (PRD → specs → milestone implementation), the spec-authoring step list with applicability flags, and prompt templates. Loads on demand only when the trigger matches. |

Content-only — no binary.

## Two applicability gates

This extension is gated at both levels, so the methodology never leaks into
workspaces or sessions that don't want it:

1. **Install-time (opt-in):** only software-oriented workspaces install it; the
   trigger rule and note exist only there.
2. **Runtime (load-on-demand):** even where installed, the trigger fires only
   for a greenfield build that wants a PRD/spec. The large note body stays out
   of the always-loaded prompt until the trigger matches.

## Authoring / contributing

See the Consigliere [extension authoring guide](https://github.com/mnemcik/consigliere/blob/main/EXTENSIONS.md).
The manifest is `cg-extension.json`; CI validates it against the
[canonical schema](https://github.com/mnemcik/cg-extensions-registry/blob/main/schema/cg-extension.schema.json).

## License

MIT — see the [LICENSE](../LICENSE) at the monorepo root.
