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
    summary.md           counts, releases, merged PRs, new issues, rolled-up bot items
    chunk-NN.md          per-thread text for the human-signal threads, ~60k chars each
    manifest.json        cursor in/out, counts, chunk list, thread numbers per chunk

Prints manifest.json to stdout. The next run's --since is manifest["cursor_out"].

Endpoints (all filter on updated_at "after" --since; see SKILL.md next to this file):
    GET  /repos/{o}/{r}/issues?state=all&sort=updated&direction=asc&since=   (issues + PRs)
    GET  /repos/{o}/{r}/issues/comments?sort=updated&direction=asc&since=
    GET  /repos/{o}/{r}/pulls/comments?sort=updated&direction=asc&since=
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
BOT_RE = re.compile(r"(\[bot\]$|^dependabot|^renovate|^github-actions|^codecov|^copilot)", re.I)


def parse_since(s: str) -> dt.datetime:
    now = dt.datetime.now(dt.timezone.utc)
    if m := re.fullmatch(r"(\d+)d", s):
        return now - dt.timedelta(days=int(m.group(1)))
    if s.isdigit():
        return dt.datetime.fromtimestamp(int(s), dt.timezone.utc)
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(dt.timezone.utc)


def iso(d: dt.datetime) -> str:
    return d.strftime("%Y-%m-%dT%H:%M:%SZ")


def ts(s: str | None) -> dt.datetime | None:
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


def gh_paginate(path: str) -> list:
    """REST GET with --paginate --slurp: one JSON array of pages, flattened."""
    out = subprocess.run(["gh", "api", "--paginate", "--slurp", path],
                         capture_output=True, text=True, check=True).stdout
    return [item for page in json.loads(out) for item in page]


def gh_get(path: str):
    out = subprocess.run(["gh", "api", path], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


DISC_QUERY = """
query($owner:String!, $name:String!, $after:String) {
  repository(owner:$owner, name:$name) {
    discussions(first:50, after:$after, orderBy:{field:UPDATED_AT, direction:DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number title url createdAt updatedAt closed
        author { login }
        category { name }
        body
        comments(last:50) {
          nodes { author { login } createdAt updatedAt body
                  replies(last:20) { nodes { author { login } createdAt updatedAt body } } }
        }
      }
    }
  }
}"""


def fetch_discussions(owner: str, name: str, since: dt.datetime) -> list:
    found, after = [], None
    while True:
        args = ["gh", "api", "graphql", "-f", f"query={DISC_QUERY}",
                "-F", f"owner={owner}", "-F", f"name={name}"]
        if after:
            args += ["-F", f"after={after}"]
        data = json.loads(subprocess.run(args, capture_output=True, text=True, check=True).stdout)
        conn = data["data"]["repository"]["discussions"]
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
    text = (text or "").strip()
    # Drop HTML comments (PR templates, bot metadata) and collapse blank runs.
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text if len(text) <= n else text[:n] + f"\n…[truncated, {len(text) - n} more chars]"


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
    q = f"sort=updated&direction=asc&per_page=100&since={iso(since)}"

    issues = [i for i in gh_paginate(f"{base}/issues?state=all&{q}") if ts(i["updated_at"]) > since]
    (out / "raw/issues.json").write_text(json.dumps(issues, indent=1))
    if a.count_only:
        prs = sum(1 for i in issues if "pull_request" in i)
        bots = sum(1 for i in issues if BOT_RE.search(login(i["user"])))
        res = {"repo": a.repo, "since": iso(since), "threads": len(issues), "prs": prs,
               "issues": len(issues) - prs, "bot_authored": bots,
               "new_since": sum(1 for i in issues if ts(i["created_at"]) > since)}
        print(json.dumps(res, indent=1))
        return 0

    icomments = [c for c in gh_paginate(f"{base}/issues/comments?{q}") if ts(c["updated_at"]) > since]
    rcomments = [c for c in gh_paginate(f"{base}/pulls/comments?{q}") if ts(c["updated_at"]) > since]
    releases = [r for r in gh_paginate(f"{base}/releases?per_page=100")
                if r.get("published_at") and ts(r["published_at"]) > since]
    discussions = fetch_discussions(owner, name, since)

    # Reviews have no `since` filter: fetch per PR that was active in the window.
    reviews: dict[int, list] = {}
    for i in issues:
        if "pull_request" in i:
            rv = [r for r in gh_paginate(f"{base}/pulls/{i['number']}/reviews?per_page=100")
                  if r.get("submitted_at") and ts(r["submitted_at"]) > since]
            if rv:
                reviews[i["number"]] = rv

    for fname, obj in [("issue-comments", icomments), ("review-comments", rcomments),
                       ("releases", releases), ("discussions", discussions), ("reviews", reviews)]:
        (out / f"raw/{fname}.json").write_text(json.dumps(obj, indent=1))

    # ---- group per thread -------------------------------------------------------------
    events: dict[int, list] = defaultdict(list)  # number -> [(time, author, kind, body)]
    for c in icomments:
        n = int(c["issue_url"].rsplit("/", 1)[1])
        edited = " (edited; created before window)" if ts(c["created_at"]) <= since else ""
        events[n].append((c["created_at"], login(c["user"]), "comment" + edited, c["body"]))
    for c in rcomments:
        n = int(c["pull_request_url"].rsplit("/", 1)[1])
        where = f"review comment on `{c.get('path')}`"
        events[n].append((c["created_at"], login(c["user"]), where, c["body"]))
    for n, rv in reviews.items():
        for r in rv:
            events[n].append((r["submitted_at"], login(r["user"]), f"review: {r['state']}", r.get("body")))

    by_num = {i["number"]: i for i in issues}
    signal, mechanical = [], []
    for n, i in sorted(by_num.items()):
        human_events = [e for e in events.get(n, []) if not BOT_RE.search(e[1])]
        bot_author = bool(BOT_RE.search(login(i["user"])))
        new = ts(i["created_at"]) > since
        settled = any(ts(x) and ts(x) > since for x in
                      (i.get("closed_at"), (i.get("pull_request") or {}).get("merged_at")))
        # Signal = a human did something in the window: opened it, commented/reviewed,
        # or it was closed/merged. Bot-only touches (stale marks, CI) are rolled up.
        human_touch = human_events or (new and not bot_author) or (settled and not bot_author)
        (signal if human_touch else mechanical).append(i)

    def thread_text(i: dict) -> str:
        n = i["number"]
        is_pr = "pull_request" in i
        kind = "PR" if is_pr else "Issue"
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
        evs = sorted(events.get(n, []))
        lines = [f"\n**[{t[:16].replace('T', ' ')}] `{who}` — {k}:**\n{cap(b, COMMENT_CAP)}\n"
                 for t, who, k, b in evs]
        if not new and not evs:
            lines = ["\n_(updated in window with no new comments: state/label/metadata change)_\n"]
        return head + body + "".join(lines) + "\n---\n"

    def disc_text(d: dict) -> str:
        new = ts(d["createdAt"]) > since
        parts = [f"## Discussion #{d['number']}: {d['title']}\n- by `{login(d['author'])}` · "
                 f"{d['category']['name']} · opened {d['createdAt'][:10]}{' (NEW)' if new else ''}"
                 f"{' · closed' if d['closed'] else ''}\n- {d['url']}\n"]
        if new:
            parts.append(f"\n**Opening post:**\n{cap(d['body'], BODY_CAP)}\n")
        flat = []
        for c in d["comments"]["nodes"]:
            flat.append((c["createdAt"], login(c["author"]), "comment", c["body"], c["updatedAt"]))
            for r in c["replies"]["nodes"]:
                flat.append((r["createdAt"], login(r["author"]), "reply", r["body"], r["updatedAt"]))
        for t, who, k, b, u in sorted(flat):
            if ts(u) > since:
                parts.append(f"\n**[{t[:16].replace('T', ' ')}] `{who}` — {k}:**\n{cap(b, COMMENT_CAP)}\n")
        return "".join(parts) + "\n---\n"

    blocks = [(i["number"], thread_text(i)) for i in signal] + \
             [(f"D{d['number']}", disc_text(d)) for d in discussions]

    chunks, cur, cur_nums = [], "", []
    for num, text in blocks:
        if cur and len(cur) + len(text) > CHUNK_CHARS:
            chunks.append((cur, cur_nums))
            cur, cur_nums = "", []
        cur += text
        cur_nums.append(num)
    if cur:
        chunks.append((cur, cur_nums))
    for old in out.glob("chunk-*.md"):
        old.unlink()
    chunk_index = []
    for k, (text, nums) in enumerate(chunks, 1):
        p = out / f"chunk-{k:02d}.md"
        p.write_text(f"# {a.repo} — activity {iso(since)} → {iso(cursor_out)} — chunk {k}/{len(chunks)}\n\n{text}")
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
         f"{sum(map(len, reviews.values()))} reviews",
         f"- Signal threads (in chunks): {len(signal)} · rolled-up bot threads: {len(mechanical)}\n",
         "## Releases\n"]
    s += [f"- **{r['tag_name']}** ({r['published_at'][:10]}){' prerelease' if r['prerelease'] else ''}: "
          f"{r['html_url']}" for r in sorted(releases, key=lambda r: r["published_at"])] or ["- none"]
    s += ["\n## Merged PRs\n"]
    s += [f"- #{i['number']} {i['title']} (`{login(i['user'])}`, {i['pull_request']['merged_at'][:10]})"
          for i in sorted(merged, key=lambda i: i["pull_request"]["merged_at"])] or ["- none"]
    s += ["\n## Rolled-up bot threads (not in chunks)\n"]
    s += [f"- #{i['number']} {i['title']} (`{login(i['user'])}`, {i['state']})" for i in mechanical] or ["- none"]
    (out / "summary.md").write_text("\n".join(s) + "\n")

    manifest = {
        "repo": a.repo, "cursor_in": iso(since), "cursor_out": iso(cursor_out),
        "threads": len(issues), "discussions": len(discussions), "signal_threads": len(signal),
        "bot_threads_rolled_up": len(mechanical), "issue_comments": len(icomments),
        "review_comments": len(rcomments), "reviews": sum(map(len, reviews.values())),
        "releases": [r["tag_name"] for r in releases], "merged_prs": len(merged),
        "chunks": chunk_index, "out": str(out.resolve()),
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    print(json.dumps({k: v for k, v in manifest.items() if k != "chunks"} |
                     {"chunks": [(c["file"], c["chars"], len(c["threads"])) for c in chunk_index]}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
