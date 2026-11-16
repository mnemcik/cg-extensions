"""Offline tests for gh-repo-watch.py (no network, no gh): run with
python -m unittest discover -s github-digest/tests -v"""
import datetime as dt
import importlib.util
import json
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "templates/skill/gh-repo-watch.py"
spec = importlib.util.spec_from_file_location("gh_repo_watch", SCRIPT)
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)


T0 = dt.datetime(2026, 11, 1, tzinfo=dt.timezone.utc)


def at(sec: int) -> str:
    return w.iso(T0 + dt.timedelta(seconds=sec))


class FakeAPI:
    """A live list served like GitHub: `since` (updated at or after, inclusive like
    the real API), sort=updated asc,
    per_page and page. `on_request(n, api)` mutates the list between requests."""

    def __init__(self, items, on_request=None):
        self.items = {i: s for i, s in items}  # id -> updated second
        self.on_request = on_request
        self.n = 0

    def __call__(self, args):
        self.n += 1
        if self.on_request:
            self.on_request(self.n, self)
        url = args[-1]
        q = dict(kv.split("=", 1) for kv in url.split("?", 1)[1].split("&"))
        since = w.ts(q["since"])
        per, page = int(q["per_page"]), int(q.get("page", 1))
        rows = sorted((s, i) for i, s in self.items.items() if T0 + dt.timedelta(seconds=s) >= since)
        rows = rows[(page - 1) * per: page * per]
        return json.dumps([{"id": i, "updated_at": at(s)} for s, i in rows])


class Keyset(unittest.TestCase):
    def setUp(self):
        self._run_gh, self._page = w.run_gh, w.PAGE
        w.PAGE = 2
        w.STATS.update(keyset_requests=0, offset_fallbacks=0, unverified_seconds=[])

    def tearDown(self):
        w.run_gh, w.PAGE = self._run_gh, self._page

    def fetch(self, api):
        w.run_gh = api
        return sorted(i["id"] for i in w.gh_since_keyset("repos/o/r/issues?state=all", T0))

    def test_reads_everything(self):
        api = FakeAPI([(i, 10 * i) for i in range(1, 8)])
        self.assertEqual(self.fetch(api), list(range(1, 8)))

    def test_deletion_mid_run_skips_nothing(self):
        # Offset paging would skip item 3 here: item 1 vanishes after the first page.
        def delete_first(n, api):
            if n == 2:
                api.items.pop(1, None)
        api = FakeAPI([(i, 10 * i) for i in range(1, 6)], delete_first)
        self.assertEqual(self.fetch(api), [1, 2, 3, 4, 5])

    def test_repeated_deletions_skip_nothing(self):
        # The case two passes could miss: a deletion ahead of the next item on every request.
        def delete_oldest(n, api):
            if n > 1 and api.items:
                api.items.pop(min(api.items, key=api.items.get))
        api = FakeAPI([(i, 10 * i) for i in range(1, 9)], delete_oldest)
        got = self.fetch(api)
        self.assertTrue(api.items, "the scenario must leave survivors")
        # Every item that existed for the whole run is read; deleted ones may or may not be.
        self.assertTrue(set(api.items) <= set(got), (sorted(api.items), got))
        self.assertEqual(len(got), len(set(got)))

    def test_update_mid_run_is_still_read(self):
        def bump(n, api):
            if n == 2:
                api.items[1] = 1000  # item 1 updated: moves to the end
        api = FakeAPI([(i, 10 * i) for i in range(1, 6)], bump)
        self.assertEqual(self.fetch(api), [1, 2, 3, 4, 5])

    def test_same_second_ties_at_page_boundary(self):
        api = FakeAPI([(1, 10), (2, 20), (3, 20), (4, 20), (5, 30)])
        self.assertEqual(self.fetch(api), [1, 2, 3, 4, 5])

    def test_more_than_a_page_in_one_second_falls_back(self):
        api = FakeAPI([(i, 20) for i in range(1, 6)] + [(9, 40)])
        self.assertEqual(self.fetch(api), [1, 2, 3, 4, 5, 9])
        self.assertEqual(w.STATS["offset_fallbacks"], 1)


    def test_deletion_during_fallback_is_recovered(self):
        # Five items in one second (page size 2) force the fallback. An item vanishes
        # while page 2 of the first offset read is requested (request 4), so that read
        # skips item 3; the re-reads recover it and then agree.
        def delete_during_fallback(n, api):
            if n == 4:
                api.items.pop(1, None)
        api = FakeAPI([(i, 20) for i in range(1, 6)] + [(9, 40)], delete_during_fallback)
        got = self.fetch(api)
        self.assertTrue(set(api.items) <= set(got), (sorted(api.items), got))
        self.assertEqual(w.STATS["unverified_seconds"], [])

    def test_unstable_fallback_is_reported(self):
        # The list keeps changing inside the stalled second on every request: reads
        # never agree, so the second is reported for the caller to hold the cursor.
        counter = iter(range(100, 10_000))
        def churn(n, api):
            if n > 1:
                api.items.pop(min(k for k, s in api.items.items() if s == 20), None)
                api.items[next(counter)] = 20
        api = FakeAPI([(i, 20) for i in range(1, 6)] + [(9, 40)], churn)
        self.fetch(api)
        self.assertEqual(w.STATS["unverified_seconds"], [at(20)])


class Paginate(unittest.TestCase):
    def test_dedupes_by_id(self):
        old = w.run_gh
        try:
            w.run_gh = lambda args: json.dumps([[{"id": 1}, {"id": 2}], [{"id": 2}, {"id": 4}]])
            self.assertEqual([i["id"] for i in w.gh_paginate("x")], [1, 2, 4])
        finally:
            w.run_gh = old


class ParseSince(unittest.TestCase):
    def test_naive_date_is_utc(self):
        self.assertEqual(w.iso(w.parse_since("2026-11-16")), "2026-11-16T00:00:00Z")

    def test_epoch_and_offset(self):
        self.assertEqual(w.iso(w.parse_since("1794547684")), "2026-11-13T05:28:04Z")
        self.assertEqual(w.iso(w.parse_since("2026-11-16T01:00:00+01:00")), "2026-11-16T00:00:00Z")

    def test_days(self):
        delta = dt.datetime.now(dt.timezone.utc) - w.parse_since("3d")
        self.assertAlmostEqual(delta.total_seconds(), 3 * 86400, delta=5)


class Cap(unittest.TestCase):
    def test_empty_bodies(self):
        for body in (None, "", "<!-- a -->", "<!-- a -->\n\n<!-- b -->  "):
            self.assertEqual(w.cap(body, 100), "> _(empty)_")

    def test_quotes_headings_and_truncates(self):
        out = w.cap("## Heading\ntext", 100)
        self.assertEqual(out, "> ## Heading\n> text")
        self.assertIn("…[truncated", w.cap("x" * 50, 10))


class IsBot(unittest.TestCase):
    def test_detection(self):
        self.assertTrue(w.is_bot({"login": "Copilot", "type": "Bot"}))
        self.assertTrue(w.is_bot({"login": "x", "__typename": "Bot"}))
        self.assertTrue(w.is_bot({"login": "dependabot[bot]", "type": "User"}))
        self.assertFalse(w.is_bot({"login": "copilot-fan", "type": "User"}))
        self.assertFalse(w.is_bot(None))


if __name__ == "__main__":
    unittest.main()
