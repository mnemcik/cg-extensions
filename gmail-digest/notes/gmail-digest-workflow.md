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

1. **Identify the target.** Match the user's request to a target file in `notes/gmail-digest-targets/`. Read it to get the Gmail label, output slug, and digest history.
2. **Reconcile the history with what's on disk.** List `notes/<slug>-digest-*/` and compare it with the target's Digest History table. A digest folder can arrive without a history row or a `notes/INDEX.md` pointer (for example by a bulk import), and a row can lack its `Last Message Epoch`. Trusting the table alone re-processes covered work; trusting the folders alone loses the epoch. Backfill any missing row and pointer as part of this run.
3. **Run the digest:** search `label:<label-name> is:unread` (or run the `gmail-digest` skill if you have it: `/gmail-digest <label-name>`).
   - **Select with `is:unread`, not `after:<epoch>`.** Gmail evaluates `after:` per *message* but returns whole *threads*, so a long-running thread with one recent message brings its entire, already-digested history back. On one busy label, `after:<last-epoch>` returned 500+ threads where `is:unread` returned the real work set. Every digest ends with its messages marked read (step 8), so unread means not yet digested. This assumes the user doesn't read these notifications in Gmail itself; if they do, fall back to the epoch. `is:unread` still returns whole threads, so drop messages older than the last epoch: they were covered by an earlier digest.
   - **`label:` query gotcha:** filter by the label **display name** (`label:github/your-repo`), **not** the internal label ID. Despite tool descriptions that claim `label:` accepts label IDs, `label:Label_6862811504768141164` returns `{}` (silent empty) while the name form works. The label ID is still useful for label/unlabel mutation calls — just not for search queries.
   - **Search results cap each thread's messages.** A Gmail MCP's thread search may return only some of each thread's messages (5 in the tools this was written against), so per-thread message counts and "latest activity" dates from search are lower bounds. A thread whose visible messages are months old can still hold unread messages from today. Read the thread itself for the real set.
   - **`resultCountEstimate` is not a count.** It has under-reported by 3× or more (402 for 1,493 threads). Page until there is no `nextPageToken`; don't size the job from the estimate.
   - **If the result is large,** see [Large backlogs](#large-backlogs) before reading anything.
4. **Record the latest message timestamp.** After fetching messages, find the most recent message's `Date` header and convert it to a Unix epoch. This becomes the `Last Message Epoch` for the history row.
5. **Output goes to:** `notes/<slug>-digest-YYYY-MM-DD/` (today's date, slug from the target file).
6. **Update the target file** — add a row to the Digest History table including the `Last Message Epoch`.
7. **Update `notes/INDEX.md`** — add a link to the new `analysis.md` under Reference.
8. **Mark the digested messages as read.** If your Gmail MCP can't modify messages, ask the user to do it. The next digest selects by `is:unread`, so anything left unread is digested again.

## Large backlogs

When a target hasn't been synced for weeks, reading everything in one context doesn't fit: a 58-day gap on one label was 1,493 threads, 5,094 new messages and roughly 750k tokens raw. Two strategies work without sampling:

- **A — filter, then read in chunks.** Strip the corpus down and read it sequentially in one context. Cheaper, and one reader's judgment spans the whole corpus. Pick it when snippets carry enough signal and much of the corpus is mechanical (release housekeeping, version bumps, bot chatter).
- **B — fan out to subagents.** Give full thread text to parallel subagents. More expensive, but every thread is read in full, with no snippet capping, and wall-clock time is parallel. Pick it when per-thread substance matters (design arguments, review reasoning).

### Paging the result to disk (both strategies)

1. **Page every thread to disk first; don't read pages inline.** Save each search page to a file and take `nextPageToken` from it with `jq`. **Never truncate the token** — a shortened token in a probe is silently invalid and restarts paging from the top. Stop when the response has no `nextPageToken`.
2. **Audit coverage independently of the paging loop.** Whether a client saves a large tool result to a file can depend on its size, so one small page may come back inline and be missed by a glob over the saved pages, leaving a hole with no error. For a GitHub notification label, issue and PR numbers give a free continuity check. For example, with `rows` holding the paged threads:

   ```python
   import re
   nums = {int(m.group(1)) for r in rows if (m := re.search(r'\((?:Issue|PR) #(\d+)\)', r.subject))}
   missing = [n for n in range(min(nums), max(nums)) if n not in nums]   # expect only genuinely absent numbers
   ```

   A contiguous run of missing numbers is a lost page, not a quiet week. Recover it with a date-bounded query for that window (`after:<epoch> before:<epoch>`, from the neighbouring pages' dates), not by paging again from the start: page tokens are positional, so re-walking is slow.

### Strategy A — filter, then read in chunks

1. **Keep only genuinely new messages.** Threads carry history from before the last digest. Flatten to messages, de-duplicate by message id, and keep those newer than the last epoch.
2. **Classify signal vs. mechanical before reading.** Bucket items by title pattern and roll the mechanical ones up quantitatively (counts, a release table) instead of narrating them. On the 58-day backlog this removed 300 items, about 180k tokens.
3. **Strip notification boilerplate.** Trailers such as "Reply to this email directly…", "You are receiving this because…" and `Message ID:` are around 40% of a GitHub notification snippet. Remove them and cap each snippet (~400 characters).
4. **Chunk to ~60k characters (~15k tokens) per file and read sequentially,** writing one `batch-NN.md` per chunk as you finish it. Read the chunks with your client's file-read tool, within its per-call limit, rather than printing them through a shell.
5. **Say in `analysis.md` what was rolled up and what was read in full.** A digest that silently skips part of its corpus reads as complete when it isn't.

For scale: the 58-day backlog took 11 signal chunks (~136k tokens read). If your projection is much larger, tell the user the size before starting rather than half-finishing.

### Strategy B — fan out to subagents

1. **Enumerate in a subagent.** One agent pages the search and writes a `<thread-id>\t<date>\t<subject>` TSV, returning only counts and the file path, so raw pages never enter the orchestrating context.
2. **Split into batches of ~25 threads.** Give every batch agent the same instruction file (domain context, per-entry output format, known gotchas) plus its own batch file and output path. Keeping the instructions in a file keeps each launch message small.
3. **Launch in waves.** Clients cap how many subagents run at once; relaunch rejected batches as slots free up.
4. **A batch file existing doesn't mean it is finished.** Agents append as they go, so check each output's entry count against its batch before merging. Copying output while agents still write silently truncates the digest.
5. **Key entries by item number, so resuming is cheap.** If agents die mid-run, diff the item numbers in each output against its batch, write the uncovered ones to a resume file per batch, and relaunch pointed at those, told to append and not re-fetch.
6. **Merge in a dedicated synthesis agent.** It reads all batch files and writes `analysis.md` to a prescribed section structure; spot-check a few load-bearing claims against the batch sources yourself.

**Coverage check:** item numbers in the batch inputs minus those in the outputs should be empty or explainable. Apparent gaps are usually duplicates folded into a sibling entry on purpose (an issue and its Discussion mirror, two notification threads for one PR); grep the number in the output text before treating it as missed.

## Conventions

- **Output structure:** a directory with `batch-NN.md` files + a merged `analysis.md`. **`analysis.md` is a note:** give it the workspace's standard note metadata (category, tags, **areas**), plus source, period, volume and the last message epoch. The mandatory areas are easy to omit when the analysis follows a custom section outline.
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
