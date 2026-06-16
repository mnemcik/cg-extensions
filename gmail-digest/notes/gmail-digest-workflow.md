# Gmail Digest — Workflow

## Meta

- **Category:** `workflow`
- **Tags:** `digest`, `gmail`, `monitoring`

## Summary

Generic process for producing a digest of unread Gmail notifications for any label. Each monitored label has its own **target file** (see Monitored Targets below) holding label-specific context and digest history. The trigger rule for this workflow is installed by the `gmail-digest` extension; the list of targets you monitor is yours and lives in your workspace.

## Prerequisites

- A Gmail MCP (or equivalent Gmail access) configured in your client, exposing thread search and read.
- One target file per monitored label in `notes/gmail-digest-targets/` (copy `templates/gmail-digest-target.md` to start).

## Process

0. **Create an ephemeral worktree and work from it.** The writes in this workflow land in `notes/gmail-digest-targets/<label>.md` and `notes/<slug>-digest-YYYY-MM-DD/` — both in the shared working tree. Writing from the main workspace while other sessions are active risks leaking another session's staged files into your commit, which is exactly what per-session worktree isolation prevents. Create the worktree (slug format: `digest-<target>-<YYYY-MM-DD>`):

   ```sh
   path=$(cg worktree create digest-<target>-<YYYY-MM-DD>) && cd "$path"
   ```

   At end-of-digest, land and remove (from the main workspace):

   ```sh
   cg worktree land
   cg worktree remove digest-<target>-<YYYY-MM-DD>
   ```

1. **Identify the target.** Match the user's request to a target file in `notes/gmail-digest-targets/`. Read it to get the Gmail label, output slug, and last sync timestamp.
2. **Find the last sync timestamp.** Check the target's Digest History table for the most recent entry's `Last Message Epoch` value.
3. **Run the digest:** search the label with query `after:<epoch>` using the epoch from step 2 (or run the `gmail-digest` skill if you have it: `/gmail-digest <label-name>`). Gmail's `after:` operator accepts Unix epoch seconds for precise filtering (e.g., `after:1713100800`).
   - **`label:` query gotcha:** filter by the label **display name** (`label:github/your-repo`), **not** the internal label ID. Despite tool descriptions that claim `label:` accepts label IDs, `label:Label_6862811504768141164` returns `{}` (silent empty) while the name form works. The label ID is still useful for label/unlabel mutation calls — just not for search queries.
4. **Record the latest message timestamp.** After fetching messages, find the most recent message's `Date` header and convert it to a Unix epoch. This becomes the `Last Message Epoch` for the history row.
5. **Output goes to:** `notes/<slug>-digest-YYYY-MM-DD/` (today's date, slug from the target file).
6. **Update the target file** — add a row to the Digest History table including the `Last Message Epoch`.
7. **Remind the user to mark messages as read.** If your Gmail MCP can't modify messages, prompt the user to mark the synced messages as read so they aren't re-processed on the next sync.
8. **Update `notes/INDEX.md`** — add a link to the new `analysis.md` under Reference.

## Conventions

- **Output structure:** a directory with `batch-NN-chunkN.md` files + a merged `analysis.md`.
- **No project needed** — digests are recurring reference activities. Skip project identification, but the worktree requirement still applies (enforced by the session-start gate the framework installs).
- **Trigger phrases:** "check X updates", "what's new in X", "digest X", "catch up on X".
- **Gotcha — `label:` search needs the NAME, not the ID** (see step 3). The label ID is only for the mutation tools. Target files store the ID for reference, but build the search query from the name.

## Monitored Targets

Target files live in `notes/gmail-digest-targets/`. Each file (from `templates/gmail-digest-target.md`) contains:
- Gmail label name and ID
- What the label tracks (repo, service, tool)
- Domain context that helps analysis understand the subject
- A digest history table

Define one target file per label you want to monitor; this workflow reads them.

## Related

- Skill: `gmail-digest` (optional — the marketplace skill that runs the analysis pass).
- Target files: `notes/gmail-digest-targets/`; template: `templates/gmail-digest-target.md`.
