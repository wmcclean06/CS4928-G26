#!/usr/bin/env python3
"""
Compare an independent re-run of the CS4928-G26 pipeline against the
recorded run.

  python compare_runs.py <recorded repo folder> <re-run repo folder>

Checks, for each of the 10 sample PRs:
  - the request sent to callgraph-server is identical
  - PageRank sum equal (to 1e-9 relative; last-digit float noise is ignored)
  - impact level 1 and 3: same methods (anonymous-class IDs ignored), same changed/affected/terminal
    flags, same set of call edges (order is ignored: the server returns sets)
  - a PR rejected in one run is rejected in the other (#8600)
and that results/rq1_metrics.csv gives the same categories and risk scores.
Prints MATCH / DIFF per item and an overall verdict. Reads only; writes nothing.
"""
import csv
import json
import math
import re
import sys
from collections import Counter
from pathlib import Path

# JavaParser names each anonymous class "Anonymous-<random UUID>", so the same
# method gets a different name in every graph build. Replace the UUID with a
# placeholder before comparing; Counter (not set) keeps duplicates distinct.
ANON = re.compile(r"Anonymous-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")


def norm(s):
    return ANON.sub("Anonymous-*", s) if isinstance(s, str) else s

PRS = [8349, 8429, 8458, 8537, 8600, 8607, 8621, 8638, 8640, 8647]


def load(p):
    return json.loads(Path(p).read_text(encoding="utf-8-sig"))


def node_key(n):
    return (norm(n.get("functionSignature") or n.get("signature")),
            bool(n.get("changed")), bool(n.get("affected")), bool(n.get("terminal")))


def edge_key(e):
    return tuple(sorted((k, norm(str(v))) for k, v in e.items()))


def impact_sets(p):
    d = load(p) or {}
    return (Counter(node_key(n) for n in d.get("nodes", [])),
            Counter(edge_key(e) for e in d.get("edges", [])))


def main(a, b):
    a, b = Path(a), Path(b)
    ca, cb = a / "results/raw/callgraph", b / "results/raw/callgraph"
    diffs = 0

    def report(ok, what, detail=""):
        nonlocal diffs
        diffs += 0 if ok else 1
        print(f"{'MATCH' if ok else 'DIFF '}  {what}{('  ' + detail) if detail else ''}")

    for n in PRS:
        err_a, err_b = (ca / f"pr_{n}_error.json").exists(), (cb / f"pr_{n}_error.json").exists()
        if err_a or err_b:
            report(err_a and err_b, f"#{n} rejected by server in both runs",
                   "" if err_a and err_b else f"recorded={err_a} rerun={err_b}")
            continue
        report(load(ca / f"pr_{n}_request.json") == load(cb / f"pr_{n}_request.json"), f"#{n} request")
        pa, pb = load(ca / f"pr_{n}_pagerank.json"), load(cb / f"pr_{n}_pagerank.json")
        same = (pa == pb) or (pa is not None and pb is not None and math.isclose(pa, pb, rel_tol=1e-9, abs_tol=1e-15))
        report(same, f"#{n} pagerank", f"recorded={pa} rerun={pb}")
        for lvl in (1, 3):
            na, ea = impact_sets(ca / f"pr_{n}_impact_l{lvl}.json")
            nb, eb = impact_sets(cb / f"pr_{n}_impact_l{lvl}.json")
            detail = "" if (na == nb and ea == eb) else (
                f"methods only in recorded={len(na - nb)}, only in rerun={len(nb - na)}; "
                f"edges only in recorded={len(ea - eb)}, only in rerun={len(eb - ea)}")
            report(na == nb and ea == eb,
                   f"#{n} impact level {lvl} ({sum(nb.values())} methods, {sum(eb.values())} edges)", detail)

    def rows(p):
        with open(p, newline="", encoding="utf-8-sig") as f:
            return {r["pr"]: r for r in csv.DictReader(f)}
    ra, rb = rows(a / "results/rq1_metrics.csv"), rows(b / "results/rq1_metrics.csv")
    cols = ["impact_cat", "buggy_cat", "size_cat", "churn_cat", "merge_cat", "risk_score", "risk_cat", "scored"]
    for pr in sorted(set(ra) | set(rb), key=int):
        x, y = ra.get(pr), rb.get(pr)
        bad = [c for c in cols if not x or not y or x[c] != y[c]]
        report(not bad, f"#{pr} rq1_metrics categories and risk",
               f"differs in {bad}" if bad else f"risk {y['risk_score'] or 'not scored'} {y['risk_cat']}")

    print()
    print("VERDICT: re-run matches the recorded run" if diffs == 0 else f"VERDICT: {diffs} difference(s), see DIFF lines")
    return 0 if diffs == 0 else 1


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
