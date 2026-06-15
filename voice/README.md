# voice

A [Consigliere](https://github.com/mnemcik/consigliere) extension that makes
Claude **draft outbound messages in your own voice**.

It installs a trigger rule that loads a personal `VOICE.md` style guide before
Claude writes any message on your behalf — Slack, email, Jira comment, PR
description — plus a `VOICE.md` skeleton you fill in. The mechanism is generic;
the voice content is yours and stays in your workspace.

## Install

```sh
cg extension install cg/voice   # fully-qualified: <registry>/<extension>, requires cg v1.6.0+
# or, without the registry (this extension is a subdir of the monorepo):
cg extension install https://github.com/mnemcik/cg-extensions --path voice
```

Remove cleanly with `cg extension remove voice`; update with
`cg extension update voice`.

## First-time setup

The extension seeds a skeleton at `templates/VOICE.md`. Copy it to the workspace
root and fill it in:

```sh
cp templates/VOICE.md VOICE.md   # then edit VOICE.md with your conventions
```

The trigger rule loads the root `VOICE.md` — until you create it, drafts fall
back to Claude's default voice.

## What it contributes

| Contribution | What lands |
|--------------|-----------|
| `claude-md-sections` → `voice-trigger` | A pointer-style rule block in your `CLAUDE.md` (under an `ext:voice:section` marker) that loads `VOICE.md` before producing outbound text — and skips it for read/summarize tasks. |
| `templates` → `templates/VOICE.md` | A skeleton style guide (channels, register per mode, language conventions, punctuation quirks, vocabulary signals, greetings/closings, audience-stripping, a drafting checklist) to copy to the root and personalise. |

Content-only — no binary. The extension never ships anyone's actual voice; only
the trigger and the empty skeleton.

## Authoring / contributing

See the Consigliere [extension authoring guide](https://github.com/mnemcik/consigliere/blob/main/EXTENSIONS.md).
The manifest is `cg-extension.json`; CI validates it against the
[canonical schema](https://github.com/mnemcik/cg-extensions-registry/blob/main/schema/cg-extension.schema.json).

## License

MIT — see the [LICENSE](../LICENSE) at the monorepo root.
