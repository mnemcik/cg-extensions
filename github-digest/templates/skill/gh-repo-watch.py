#!/usr/bin/env python3
"""Pull a public GitHub repo's activity since a cursor, grouped per thread.

Replaces the Gmail-notification digest: instead of reading notification emails,
query the GitHub API directly with a `since` cursor. Read-only; uses `gh` for auth
(so the gh-account-resolver routes it like any other call).

Usage:
    gh-repo-watch.py OWNER/REPO --since 2026-11-13T09:00:00Z --out DIR
    gh-repo-watch.py OWNER/REPO --since 1794547684 --out DIR   # epoch also accepted
    gh-repo-watch.py OWNER/REPO --since 30d --out DIR --count-only

Writes to DIR:
    raw/*.json           every API result, unmodified
    summary.md           counts, releases, merged PRs, new issues, rolled-up threads
    chunk-NN.md          per-thread text for the human-signal threads, ~60k chars each
    manifest.json        cursor in/out, counts, chunk list, thread numbers per chunk

Prints manifest.json to stdout. The next run's --since is manifest["cursor_out"].

Endpoints (all filter on updated_at "after" --since; see SKILL.md next to this file):
    GET  /repos/{o}/{r}/issues?state=all&sort=updated&direction=desc&since=   (issues + PRs)
    GET  /repos/{o}/{r}/issues/comments?sort=updated&direction=desc&since=
    GET  /repos/{o}/{r}/pulls/comments?sort=updated&direction=desc&since=
    GET  /repos/{o}/{r}/pulls/{n}/reviews          (per active PR; no since filter exists)
    GET  /repos/{o}/{r}/releases                    (filtered client-side on published_at)
    POST /graphql  repository.discussions(orderBy: UPDATED_AT DESC)  (paged until older than since)
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

CHUNK_CHARS = 60_000
BODY_CAP = 3_000       # issue/PR/discussion opening post
COMMENT_CAP = 2_000    # each comment / review
BOT_RE = re.compile(r"(\[bot\]$|^dependabot$|^renovate$|^github-actions$|^codecov$)", re.I)


def is_bot(user) -> bool:
    """REST/GraphQL user is a bot: account type Bot, or a known bot login."""
    user = user or {}
    return user.get("type") == "Bot" or user.get("__typename") == "Bot" \
        or bool(BOT_RE.search(user.get("login") or ""))


def parse_since(s: str) -> dt.datetime:
    now = dt.datetime.now(dt.timezone.utc)
    if m := re.fullmatch(r"(\d+)d", s):
        return now - dt.timedelta(days=int(m.group(1)))
    if s.isdigit():
        return dt.datetime.fromtimestamp(int(s), dt.timezone.utc)
    d = dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    # A naive date/time (e.g. "2026-11-16") is UTC, never the machine's local zone.
    return d.replace(tzinfo=dt.timezone.utc) if d.tzinfo is None else d.astimezone(dt.timezone.utc)


def iso(d: dt.datetime) -> str:
    return d.strftime("%Y-%m-%dT%H:%M:%SZ")


def ts(s: str | None) -> dt.datetime | None:
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


def run_gh(args: list) -> str:
    """Run gh; on failure print gh's own error (404, auth, rate limit) and exit 1."""
    p = subprocess.run(["gh", *args], capture_output=True, text=True, encoding="utf-8")
    if p.returncode != 0:
        sys.exit(f"gh {' '.join(args[:3])}… failed (exit {p.returncode}):\n{p.stderr.strip()}")
    return p.stdout


def gh_paginate(path: str) -> list:
    """REST GET with --paginate --slurp (gh >= 2.48): pages flattened, deduplicated by id.

    Pages are offsets into a live list, so an item that changes mid-run moves. With
    updated-desc order it moves to the front, onto a page already read, which pushes
    the rest one place later: they repeat (deduplicated here) rather than get skipped.
    The moved item itself was updated after cursor_out, so the next run picks it up."""
    seen, items = set(), []
    for page in json.loads(run_gh(["api", "--paginate", "--slurp", path])):
        for item in page:
            key = item.get("id", id(item))
            if key not in seen:
                seen.add(key)
                items.append(item)
    return items


def fetch_releases(base: str, since: dt.datetime) -> list:
    """All releases, filtered on published_at. Paged fully: the list is ordered by
    created_at (the release commit's date), so no page boundary bounds published_at."""
    return [r for r in gh_paginate(f"{base}/releases?per_page=100")
            if r.get("published_at") and ts(r["published_at"]) > since]


DISC_QUERY = """
query($owner:String!, $name:String!, $after:String) {
  repository(owner:$owner, name:$name) {
    discussions(first:50, after:$after, orderBy:{field:UPDATED_AT, direction:DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number title url createdAt updatedAt closed
        author { login __typename }
        category { name }
        body
        comments(last:50) {
          nodes { author { login __typename } createdAt updatedAt body
                  replies(last:20) { nodes { author { login __typename } createdAt updatedAt body } } }
        }
      }
    }
  }
}"""


def fetch_discussions(owner: str, name: str, since: dt.datetime) -> list:
    found, after = [], None
    while True:
        args = ["gh", "api", "graphql", "-f", f"query={DISC_QUERY}",
                "-f", f"owner={owner}", "-f", f"name={name}"]
        if after:
            args += ["-f", f"after={after}"]
        data = json.loads(run_gh(args[1:]))
        repo = (data.get("data") or {}).get("repository")
        if repo is None:
            sys.exit(f"GraphQL: repository {owner}/{name} not found: {data.get('errors')}")
        conn = repo["discussions"]
        stop = False
        for n in conn["nodes"]:
            if ts(n["updatedAt"]) <= since:
                stop = True
                break
            found.append(n)
        if stop or not conn["pageInfo"]["hasNextPage"]:
            return found
        after = conn["pageInfo"]["endCursor"]


def login(u) -> str:
    return (u or {}).get("login") or "ghost"


def cap(text: str | None, n: int) -> str:
    # Drop HTML comments (PR templates, bot metadata) and collapse blank runs.
    text = re.sub(r"<!--.*?-->", "", text or "", flags=re.S)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    if len(text) > n:
        text = text[:n] + f"\n…[truncated, {len(text) - n} more chars]"
    # Quote the body so its own "## " headings can't pass for thread headers.
    return "\n".join("> " + line if line else ">" for line in text.splitlines()) or "> _(empty)_"


def write(p: Path, text: str) -> None:
    p.write_text(text, encoding="utf-8")


def bot_note(bot_evs: list) -> str:
    if not bot_evs:
        return ""
    who = sorted({e[1] for e in bot_evs})
    return f"\n_({len(bot_evs)} bot comment(s)/review(s) omitted: {', '.join(who)})_\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("repo")
    ap.add_argument("--since", required=True, help="ISO time, unix epoch, or Nd")
    ap.add_argument("--out", required=True)
    ap.add_argument("--count-only", action="store_true", help="fetch issues/PRs only, print counts")
    a = ap.parse_args()

    owner, name = a.repo.split("/", 1)
    since = parse_since(a.since)
    cursor_out = dt.datetime.now(dt.timezone.utc)  # taken before fetching: overlap, never a gap
    out = Path(a.out)
    (out / "raw").mkdir(parents=True, exist_ok=True)
    base = f"repos/{owner}/{name}"
    q = f"sort=updated&direction=desc&per_page=100&since={iso(since)}"

    issues = [i for i in gh_paginate(f"{base}/issues?state=all&{q}") if ts(i["updated_at"]) > since]
    write(out / "raw/issues.json", json.dumps(issues, indent=1))
    if a.count_only:
        prs = sum(1 for i in issues if "pull_request" in i)
        bots = sum(1 for i in issues if is_bot(i["user"]))
        res = {"repo": a.repo, "since": iso(since), "threads": len(issues), "prs": prs,
               "issues": len(issues) - prs, "bot_authored": bots,
               # Rough size for choosing a strategy, not a bound: the full run adds bot
               # threads a human commented on and rolls up human threads that saw only
               # label/state changes, neither of which --count-only can see.
               "signal_estimate": len(issues) - bots,
               "new_since": sum(1 for i in issues if ts(i["created_at"]) > since)}
        print(json.dumps(res, indent=1))
        return 0

    icomments = [c for c in gh_paginate(f"{base}/issues/comments?{q}") if ts(c["updated_at"]) > since]
    rcomments = [c for c in gh_paginate(f"{base}/pulls/comments?{q}") if ts(c["updated_at"]) > since]
    releases = fetch_releases(base, since)
    discussions = fetch_discussions(owner, name, since)

    # ---- group per thread -------------------------------------------------------------
    # event = (time, author, kind, body, is_bot)
    events: dict[int, list] = defaultdict(list)

    def edited(c: dict) -> str:
        return " (edited; created before window)" if ts(c["created_at"]) <= since else ""

    for c in icomments:
        n = int(c["issue_url"].rsplit("/", 1)[1])
        events[n].append((c["created_at"], login(c["user"]), "comment" + edited(c), c["body"], is_bot(c["user"])))
    for c in rcomments:
        n = int(c["pull_request_url"].rsplit("/", 1)[1])
        where = f"review comment on `{c.get('path')}`" + edited(c)
        events[n].append((c["created_at"], login(c["user"]), where, c["body"], is_bot(c["user"])))

    # Reviews have no `since` filter, so they cost one call per PR. Fetch them for PRs a
    # human is involved in (human author or human comment) and for bot PRs merged or
    # closed in the window (where a human approval is the likely only human act).
    # Skipped: bot PRs still open with no human comment (a human review there is missed).
    reviews: dict[int, list] = {}
    review_calls = 0
    for i in issues:
        n = i["number"]
        closed_now = bool(i.get("closed_at")) and ts(i["closed_at"]) > since
        if "pull_request" in i and (not is_bot(i["user"]) or closed_now
                                    or any(not e[4] for e in events.get(n, []))):
            review_calls += 1
            rv = [r for r in gh_paginate(f"{base}/pulls/{n}/reviews?per_page=100")
                  if r.get("submitted_at") and ts(r["submitted_at"]) > since]
            if rv:
                reviews[n] = rv
                for r in rv:
                    events[n].append((r["submitted_at"], login(r["user"]), f"review: {r['state']}",
                                      r.get("body"), is_bot(r["user"])))

    for fname, obj in [("issue-comments", icomments), ("review-comments", rcomments),
                       ("releases", releases), ("discussions", discussions), ("reviews", reviews)]:
        write(out / f"raw/{fname}.json", json.dumps(obj, indent=1))

    by_num = {i["number"]: i for i in issues}
    # Comments whose thread isn't in the issues list (a fetch race; the next run's
    # overlap catches it) are counted rather than dropped silently.
    orphans = {n: len(v) for n, v in events.items() if n not in by_num}

    signal, mechanical = [], []
    for n, i in sorted(by_num.items()):
        human_events = [e for e in events.get(n, []) if not e[4]]
        bot_author = is_bot(i["user"])
        new = ts(i["created_at"]) > since
        settled = any(ts(x) and ts(x) > since for x in
                      (i.get("closed_at"), (i.get("pull_request") or {}).get("merged_at")))
        # Signal: a human commented or reviewed in the window, or the thread is
        # human-authored and was opened, closed or merged in the window (the closer
        # may be a bot; the API doesn't say who closed it without an extra call).
        # Everything else (stale marks, CI, dependabot) is rolled up.
        human_touch = human_events or (not bot_author and (new or settled))
        (signal if human_touch else mechanical).append(i)

    def stamp(t: str) -> str:
        return t[:16].replace("T", " ")

    def thread_text(i: dict) -> str:
        n = i["number"]
        kind = "PR" if "pull_request" in i else "Issue"
        merged = (i.get("pull_request") or {}).get("merged_at")
        state = "merged " + merged[:10] if merged else i["state"] + (
            f" ({i.get('state_reason')})" if i.get("state_reason") else "")
        new = ts(i["created_at"]) > since
        labels = ", ".join(l["name"] for l in i.get("labels", []))
        head = (f"## {kind} #{n}: {i['title']}\n"
                f"- by `{login(i['user'])}` · opened {i['created_at'][:10]}"
                f"{' (NEW)' if new else ''} · state: {state}"
                f"{' · closed ' + i['closed_at'][:10] if i.get('closed_at') and not merged else ''}"
                f"{' · labels: ' + labels if labels else ''}\n- {i['html_url']}\n")
        body = f"\n**Opening post:**\n{cap(i.get('body'), BODY_CAP)}\n" if new else ""
        evs = sorted(events.get(n, []), key=lambda e: e[0])
        human = [e for e in evs if not e[4]]
        lines = [f"\n**[{stamp(t)}] `{who}` — {k}:**\n{cap(b, COMMENT_CAP)}\n" for t, who, k, b, _ in human]
        if not new and not human:
            lines = ["\n_(updated in window with no new human comments: state/label/metadata change)_\n"]
        return head + body + "".join(lines) + bot_note([e for e in evs if e[4]]) + "\n---\n"

    def disc_text(d: dict) -> str:
        new = ts(d["createdAt"]) > since
        parts = [f"## Discussion #{d['number']}: {d['title']}\n- by `{login(d['author'])}` · "
                 f"{d['category']['name']} · opened {d['createdAt'][:10]}{' (NEW)' if new else ''}"
                 f"{' · closed' if d['closed'] else ''}\n- {d['url']}\n"]
        if new:
            parts.append(f"\n**Opening post:**\n{cap(d['body'], BODY_CAP)}\n")
        flat = []
        for c in d["comments"]["nodes"]:
            flat.append((c["createdAt"], login(c["author"]), "comment", c["body"], c["updatedAt"], is_bot(c["author"])))
            for r in c["replies"]["nodes"]:
                flat.append((r["createdAt"], login(r["author"]), "reply", r["body"], r["updatedAt"], is_bot(r["author"])))
        bots = []
        for t, who, k, b, u, bot in sorted(flat, key=lambda e: e[0]):
            if ts(u) <= since:
                continue
            if bot:
                bots.append((t, who))
                continue
            k += " (edited; created before window)" if ts(t) <= since else ""
            parts.append(f"\n**[{stamp(t)}] `{who}` — {k}:**\n{cap(b, COMMENT_CAP)}\n")
        return "".join(parts) + bot_note(bots) + "\n---\n"

    blocks = [(i["number"], thread_text(i)) for i in signal] + \
             [(f"D{d['number']}", disc_text(d)) for d in discussions]

    def split_block(num, text: str) -> list:
        """Split a thread longer than a chunk at event boundaries (or, failing that,
        lines), so no chunk greatly exceeds CHUNK_CHARS. Each part keeps the header."""
        if len(text) <= CHUNK_CHARS:
            return [(num, text)]
        header = text.split("\n", 1)[0]
        pieces = re.split(r"(?=\n\*\*\[)", text)  # each event starts "\n**[time]"
        units = []
        for piece in pieces:
            while len(piece) > CHUNK_CHARS:  # one event longer than a chunk: cut by lines
                cut = piece.rfind("\n", 0, CHUNK_CHARS)
                cut = cut if cut > 0 else CHUNK_CHARS
                units.append(piece[:cut])
                piece = piece[cut:]
            units.append(piece)
        parts, cur = [], ""
        for u in units:
            if cur and len(cur) + len(u) > CHUNK_CHARS:
                parts.append(cur)
                cur = f"{header} (continued)\n"
            cur += u
        parts.append(cur)
        return [(num, p) for p in parts]

    blocks = [part for num, text in blocks for part in split_block(num, text)]
    chunks, cur, cur_nums = [], "", []
    for num, text in blocks:
        if cur and len(cur) + len(text) > CHUNK_CHARS:
            chunks.append((cur, cur_nums))
            cur, cur_nums = "", []
        cur += text
        if num not in cur_nums:
            cur_nums.append(num)
    if cur:
        chunks.append((cur, cur_nums))
    for old in out.glob("chunk-*.md"):
        old.unlink()
    chunk_index = []
    for k, (text, nums) in enumerate(chunks, 1):
        p = out / f"chunk-{k:02d}.md"
        write(p, f"# {a.repo} — activity {iso(since)} → {iso(cursor_out)} — chunk {k}/{len(chunks)}\n\n{text}")
        chunk_index.append({"file": p.name, "chars": len(text), "threads": nums})

    # ---- summary ----------------------------------------------------------------------
    merged = [i for i in issues if (i.get("pull_request") or {}).get("merged_at")
              and ts(i["pull_request"]["merged_at"]) > since]
    new_issues = [i for i in issues if "pull_request" not in i and ts(i["created_at"]) > since]
    closed_issues = [i for i in issues if "pull_request" not in i and i.get("closed_at")
                     and ts(i["closed_at"]) > since]
    s = [f"# {a.repo} — summary {iso(since)} → {iso(cursor_out)}\n",
         f"- Threads updated: {len(issues)} ({sum('pull_request' in i for i in issues)} PRs) + "
         f"{len(discussions)} discussions",
         f"- New issues: {len(new_issues)} · issues closed: {len(closed_issues)} · PRs merged: {len(merged)}",
         f"- Comments: {len(icomments)} issue/PR, {len(rcomments)} review-line, "
         f"{sum(map(len, reviews.values()))} reviews (bot comments are counted here, not narrated)",
         f"- Signal threads (in chunks): {len(signal)} · rolled-up threads: {len(mechanical)}",
         f"- Orphaned comment events (thread not in the issues list): {sum(orphans.values())}\n",
         "## Releases\n"]
    s += [f"- **{r['tag_name']}** ({r['published_at'][:10]}){' prerelease' if r['prerelease'] else ''}: "
          f"{r['html_url']}" for r in sorted(releases, key=lambda r: r["published_at"])] or ["- none"]
    s += ["\n## Merged PRs\n"]
    s += [f"- #{i['number']} {i['title']} (`{login(i['user'])}`, {i['pull_request']['merged_at'][:10]})"
          for i in sorted(merged, key=lambda i: i["pull_request"]["merged_at"])] or ["- none"]
    s += ["\n## Rolled-up threads (not in chunks): no human comment or review, and not a human thread opened/closed in the window\n"]
    s += [f"- #{i['number']} {i['title']} (`{login(i['user'])}`, {i['state']})" for i in mechanical] or ["- none"]
    write(out / "summary.md", "\n".join(s) + "\n")

    manifest = {
        "repo": a.repo, "cursor_in": iso(since), "cursor_out": iso(cursor_out),
        "threads": len(issues), "discussions": len(discussions), "signal_threads": len(signal),
        "rolled_up_threads": len(mechanical), "issue_comments": len(icomments),
        "review_comments": len(rcomments), "reviews": sum(map(len, reviews.values())),
        "review_calls": review_calls,
        "orphaned_events": orphans,
        "releases": [r["tag_name"] for r in releases], "merged_prs": len(merged),
        "chunks": chunk_index, "out": str(out.resolve()),
    }
    write(out / "manifest.json", json.dumps(manifest, indent=1))
    print(json.dumps({k: v for k, v in manifest.items() if k != "chunks"} |
                     {"chunks": [(c["file"], c["chars"], len(c["threads"])) for c in chunk_index]}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
