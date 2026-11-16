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


def pages(*ids_per_page):
    return json.dumps([[{"id": i} for i in page] for page in ids_per_page])


class PaginateReconcile(unittest.TestCase):
    def setUp(self):
        w.RECONCILED["added_by_second_pass"] = 0
        self._run_gh = w.run_gh

    def tearDown(self):
        w.run_gh = self._run_gh

    def fake(self, *responses):
        it = iter(responses)
        w.run_gh = lambda args: next(it)

    def test_deletion_between_pages_is_recovered_by_second_pass(self):
        # Live list 1..4, two per page. Item 1 is deleted after page 1 is read, so page
        # 2 (offset 2) starts at item 4 and item 3 is skipped by the first read.
        self.fake(pages([1, 2], [4]), pages([2, 3], [4]))
        got = [i["id"] for i in w.gh_paginate("x", passes=2)]
        self.assertEqual(sorted(got), [1, 2, 3, 4])
        self.assertEqual(w.RECONCILED["added_by_second_pass"], 1)

    def test_change_mid_run_repeats_are_deduplicated(self):
        # Desc order: item 3 changes after page 1 and jumps to the front; the rest shift
        # one place later, so item 2 repeats on page 2.
        self.fake(pages([1, 2], [2, 4]))
        got = [i["id"] for i in w.gh_paginate("x")]
        self.assertEqual(got, [1, 2, 4])

    def test_single_pass_reads_once(self):
        self.fake(pages([1], []))
        self.assertEqual([i["id"] for i in w.gh_paginate("x")], [1])


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
