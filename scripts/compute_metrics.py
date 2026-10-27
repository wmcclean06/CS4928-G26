#!/usr/bin/env python3
"""
Lab 4 §3/§4: compute the five CHID metrics, their categories and the risk
score for sample PRs, from the raw data only (data/raw/, results/raw/callgraph/).

Method (M1 §4, with the rules below taken from the artefact code; see the
docstrings and constants). Nothing here is tuned to results.

  impact size   sum of PageRank of the PR's changed methods, from callgraph-server
  churn ratio   share of the PR's .java files whose cumulative code churn > 5
  buggy ratio   share of the PR's .java files whose bug frequency > 0.4
  PR size       additions + deletions of the whole PR
  merge rate    author's merged / (author's PRs + 1), history only
  risk          (4*impact + 2*buggy + 1.75*size + 1.25*churn + 1*merge) / 10 * 25

History for PR P = merged PRs created before P and merged before P was created
(MERGED_BEFORE_PR_CREATED), replayed in merge order with the bot's
incremental_updateBranch rules (incrementalAnalysisMethods.js).

Outputs:
  results/rq1_metrics.csv                one row per PR (all intermediate values)
  results/metrics_detail/pr_<n>.json     per-file churn/bug values used (for tracing)

  python scripts/compute_metrics.py --selftest   # Fig. 10 check (must give 44.38, C)
  python scripts/compute_metrics.py 8349         # one PR
  python scripts/compute_metrics.py --all        # all sample PRs
  python scripts/compute_metrics.py --set event_a --all
        # Event A PRs -> results/event_a/event_a_metrics.csv, results/event_a/metrics_detail/
"""

import argparse
import csv
import json
import math
import sys
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
RESULTS = ROOT / "results"
# PR set -> (sample list, raw PR data, call-graph results, output CSV, per-PR detail folder)
SETS = {
    "m2":      (ROOT / "data" / "eligibility_log.csv", RAW / "sample", RESULTS / "raw" / "callgraph",
                RESULTS / "rq1_metrics.csv", RESULTS / "metrics_detail"),
    "event_a": (ROOT / "data" / "event_a" / "eligibility_log.csv", RAW / "event_a_sample",
                RESULTS / "event_a" / "raw" / "callgraph",
                RESULTS / "event_a" / "event_a_metrics.csv", RESULTS / "event_a" / "metrics_detail"),
}
ELIGIBILITY, SAMPLE, CALLGRAPH, OUT_CSV, DETAIL = SETS["m2"]

# --- Frozen parameters -----------------------------------------------------
# Default settings from github-bot/models/Repository.js (bounds in %).
SETTINGS = {
    "churn":  {"a": (0, 0), "b": (0, 16), "c": (16, 33), "d": (33, 50), "e": (50, 100)},
    "buggy":  {"a": (0, 0), "b": (0, 12), "c": (12, 20), "d": (20, 30), "e": (30, 100)},
    "size":   {"a": (0, 10), "b": (10, 50), "c": (50, 200), "d": (200, 1000), "e": (1000, 1000000)},
    "merge":  {"a": (93, 100), "b": (87, 93), "c": (81, 87), "d": (75, 81), "e": (0, 75)},
    "impact": {"a": (0, 10), "b": (10, 30), "c": (30, 60), "d": (60, 80), "e": (80, 100)},
    "risk":   {"a": (0, 20), "b": (20, 40), "c": (40, 60), "d": (60, 80), "e": (80, 100)},
}
WEIGHTS = {"impact": 4, "buggy": 2, "size": 1.75, "churn": 1.25, "merge": 1}  # Fig. 8 / Repository.js
CHURN_THRESHOLD = 5      # highly churned file: churn > 5  (paper's ">", per M1)
BUG_THRESHOLD = 0.4      # highly buggy file: bug frequency > 0.4  (paper's ">", per M1)
BUG_LABELS = {"bug", "Type: Bug"}   # M1 bounded decision: label only
MERGED_BEFORE_PR_CREATED = True     # history = merged before P was opened (see D3)
LETTER = {0: "A", 1: "B", 2: "C", 3: "D", 4: "E", None: ""}


def category(value, s, divide_by_hundred):
    """Port of calculateMetricCategory (incrementalAnalysisMethods.js)."""
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return None
    if divide_by_hundred:
        value = value / 100
    if s["e"][0] / 100 <= value <= s["e"][1] / 100:
        return 4
    if s["d"][0] / 100 < value <= s["d"][1] / 100:
        return 3
    if s["c"][0] / 100 < value <= s["c"][1] / 100:
        return 2
    if s["b"][0] / 100 < value <= s["b"][1] / 100:
        return 1
    if s["a"][0] / 100 <= value <= s["a"][1] / 100:
        return 0
    return None


def js_to_fixed2(x):
    """JS Number.prototype.toFixed(2) for non-negative x."""
    return float(Decimal(x).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def risk_score(cat):
    """Port of incremental_calculateRiskScore (same order of operations)."""
    if any(cat[k] is None for k in WEIGHTS):
        return None, None
    total = (WEIGHTS["impact"] * cat["impact"] + WEIGHTS["buggy"] * cat["buggy"]
             + WEIGHTS["size"] * cat["size"] + WEIGHTS["churn"] * cat["churn"]
             + WEIGHTS["merge"] * cat["merge"])
    coeff_sum = (WEIGHTS["impact"] + WEIGHTS["buggy"] + WEIGHTS["size"]
                 + WEIGHTS["churn"] + WEIGHTS["merge"])
    value = js_to_fixed2((total / coeff_sum) * 25)
    return value, category(value, SETTINGS["risk"], True)


def js_div(a, b):
    """JavaScript division (x/0 = Infinity, 0/0 = NaN)."""
    if b == 0:
        return math.nan if a == 0 else math.inf
    return a / b


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sample_numbers():
    with open(ELIGIBILITY, newline="", encoding="utf-8-sig") as f:
        return [int(r[0]) for r in list(csv.reader(f))[1:] if r and r[-1].startswith("ELIGIBLE")]


def history_prs():
    out = []
    for p in sorted((RAW / "history").glob("pr_*_java_meta.json")):
        n = int(p.name.split("_")[1])
        pr = load(RAW / "history" / f"pr_{n}.json")
        out.append({"number": n, "created_at": pr["created_at"], "merged_at": pr["merged_at"],
                    "labels": {l["name"] for l in pr["labels"]},
                    "files": load(p)["java_files"]})
    return out


def replay_branch(history, created):
    """Branch file state seen by a PR opened at `created` (incremental_updateBranch)."""
    used = [h for h in history if h["merged_at"] and h["created_at"] < created
            and (not MERGED_BEFORE_PR_CREATED or h["merged_at"] < created)]
    used.sort(key=lambda h: (h["merged_at"], h["number"]))
    branch = {}
    for h in used:
        bug = bool(BUG_LABELS & h["labels"])
        for f in h["files"]:
            path = f["path"]
            if f["status"] == "removed":
                branch.pop(path, None)
                continue
            loc = f["loc_at_head"] or 0          # getTotalLOC returns 0 when no content
            changes = f["additions"] + f["deletions"]
            e = branch.get(path)
            if e is None:                         # file not yet in branch: created
                branch[path] = {"loc": loc, "churn": js_div(changes, loc), "pr_count": 1,
                                "buggy_pr_count": 1 if bug else 0, "bug_freq": 1 if bug else 0}
            else:                                 # file modified
                total = e["loc"] * e["churn"] + changes
                e["churn"] = total / (loc if loc != 0 else 1)
                e["loc"] = loc
                if bug:
                    e["buggy_pr_count"] += 1
                e["pr_count"] += 1
                e["bug_freq"] = e["buggy_pr_count"] / e["pr_count"]
    return branch, len(used)


def merge_rate(pr_list, author, created):
    prior = [p for p in pr_list if p["user"] == author and p["created_at"] < created]
    merged = [p for p in prior if p["merged_at"] and
              (not MERGED_BEFORE_PR_CREATED or p["merged_at"] < created)]
    return len(merged) / (len(prior) + 1), len(merged), len(prior)


def compute(n, history, pr_list):
    pr = load(SAMPLE / f"pr_{n}.json")
    meta = load(SAMPLE / f"pr_{n}_java_meta.json")
    created, author = pr["created_at"], pr["user"]["login"]
    branch, n_hist = replay_branch(history, created)

    java = meta["java_files"]
    detail, churn_count, bug_count = [], 0, 0
    for f in java:
        e = branch.get(f["path"])
        churned = e is not None and e["churn"] > CHURN_THRESHOLD
        buggy = e is not None and e["bug_freq"] > BUG_THRESHOLD
        churn_count += churned
        bug_count += buggy
        detail.append({"path": f["path"], "status": f["status"], "in_history": e is not None,
                       "churn": None if e is None else e["churn"],
                       "bug_freq": None if e is None else e["bug_freq"],
                       "history_pr_count": None if e is None else e["pr_count"],
                       "highly_churned": churned, "highly_buggy": buggy})
    churn_ratio = js_div(churn_count, len(java))
    bug_ratio = js_div(bug_count, len(java))
    size = pr["additions"] + pr["deletions"]
    rate, merged, prior = merge_rate(pr_list, author, created)

    pr_file = CALLGRAPH / f"pr_{n}_pagerank.json"
    pagerank = load(pr_file) if pr_file.exists() else None

    cat = {
        "impact": None if pagerank is None else category(pagerank * 100, SETTINGS["impact"], True),
        "buggy": category(bug_ratio, SETTINGS["buggy"], False),
        "size": category(size, SETTINGS["size"], True),
        "churn": category(churn_ratio, SETTINGS["churn"], False),
        "merge": category(rate, SETTINGS["merge"], False),
    }
    risk, risk_cat = risk_score(cat)
    row = {
        "pr": n, "state": "merged" if pr["merged_at"] else pr["state"], "author": author,
        "created_at": created, "java_files": len(java), "history_prs_used": n_hist,
        "pagerank_sum": pagerank, "impact_cat": LETTER[cat["impact"]],
        "highly_buggy_files": bug_count, "buggy_ratio": bug_ratio, "buggy_cat": LETTER[cat["buggy"]],
        "pr_size": size, "size_cat": LETTER[cat["size"]],
        "highly_churned_files": churn_count, "churn_ratio": churn_ratio, "churn_cat": LETTER[cat["churn"]],
        "author_prior_prs": prior, "author_prior_merged": merged, "merge_rate": rate,
        "merge_cat": LETTER[cat["merge"]],
        "risk_score": risk, "risk_cat": LETTER[risk_cat],
        "scored": risk is not None,
    }
    return row, detail


def selftest():
    cat = {"impact": 0, "buggy": 3, "size": 3, "churn": 2, "merge": 4}   # Fig. 10: A, D, D, C, E
    value, c = risk_score(cat)
    ok = value == 44.38 and c == 2
    print(f"Fig. 10 check: risk {value}, category {LETTER[c]} -> {'PASS' if ok else 'FAIL'} (expected 44.38, C)")
    return ok


def main():
    global ELIGIBILITY, SAMPLE, CALLGRAPH, OUT_CSV, DETAIL
    ap = argparse.ArgumentParser()
    ap.add_argument("prs", nargs="*", type=int)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--set", choices=list(SETS), default="m2")
    args = ap.parse_args()
    ELIGIBILITY, SAMPLE, CALLGRAPH, OUT_CSV, DETAIL = SETS[args.set]
    if not selftest():
        sys.exit("self-test failed; not computing")
    if args.selftest and not (args.prs or args.all):
        return
    prs = sample_numbers() if args.all else args.prs
    if not prs:
        sys.exit("give PR numbers or --all")

    history = history_prs()
    pr_list = json.loads((ROOT / "data" / "arduino_pr_list.json").read_text(encoding="utf-8"))
    rows = []
    DETAIL.mkdir(parents=True, exist_ok=True)
    for n in prs:
        row, detail = compute(n, history, pr_list)
        rows.append(row)
        (DETAIL / f"pr_{n}.json").write_text(
            json.dumps({"pr": n, "files": detail}, indent=1), encoding="utf-8")
        print(f"#{n}: impact {row['impact_cat'] or '-'}  buggy {row['buggy_cat']}  size {row['size_cat']}  "
              f"churn {row['churn_cat']}  merge {row['merge_cat']}  ->  risk "
              f"{row['risk_score'] if row['scored'] else 'NOT SCORED (no PageRank result)'} {row['risk_cat']}")

    out = OUT_CSV
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
