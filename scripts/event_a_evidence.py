#!/usr/bin/env python3
"""
Event A: classify each held-out PR as correct alarm / false alarm /
missed high-impact change / correct clear, using the rules frozen in
Notes/EVENT_A_PLAN.md §3 and D6 before the run. Reads already-fetched data
only (no network); nothing here is tuned to results.

  flagged          scored and risk category B-E (score > 20)
  defect evidence  the PR has a "bug" / "Type: Bug" label, OR a later merged PR
                   with one of those labels touches at least one of the same
                   .java files ("later" = created after the held-out PR was
                   merged). For an open PR only its own label counts.
  false alarm      flagged, no defect evidence
  missed change    not flagged, defect evidence
  not scored PRs   reported with their evidence, but not counted in either

Inputs:
  data/event_a/eligibility_log.csv           the 5 held-out PRs
  results/event_a/event_a_metrics.csv        scored / risk category (compute_metrics.py --set event_a)
  data/raw/event_a_sample/pr_<n>.json        own labels, merged_at
  data/raw/event_a_sample/pr_<n>_java_meta.json   the PR's .java paths
  data/arduino_pr_list.json                  labels / created / merged of candidate later PRs
  data/raw/later_bug/pr_<m>_files.json       files of each later bug-labelled PR
Output:
  results/event_a/event_a_evidence.csv

  python scripts/event_a_evidence.py
"""

import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SAMPLE = ROOT / "data" / "raw" / "event_a_sample"
LATER_BUG = ROOT / "data" / "raw" / "later_bug"
METRICS = ROOT / "results" / "event_a" / "event_a_metrics.csv"
OUT = ROOT / "results" / "event_a" / "event_a_evidence.csv"
BUG_LABELS = {"bug", "Type: Bug"}           # M1 bounded decision: label only
FLAG_CATS = {"B", "C", "D", "E"}            # D6: flagged = category B or worse


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    with open(ROOT / "data" / "event_a" / "eligibility_log.csv", newline="", encoding="utf-8-sig") as f:
        prs = [int(r[0]) for r in list(csv.reader(f))[1:] if r and r[-1].startswith("ELIGIBLE")]
    with open(METRICS, newline="", encoding="utf-8") as f:
        metrics = {int(r["pr"]): r for r in csv.DictReader(f)}
    pr_list = load(ROOT / "data" / "arduino_pr_list.json")

    # Candidate later bug-fix PRs: merged, bug-labelled (labels as in the cached list,
    # the same source fetch_pr_data.py used for the later_bug group).
    later = [p for p in pr_list if p["merged_at"] and BUG_LABELS & set(p["labels"])]

    rows = []
    for n in prs:
        pr = load(SAMPLE / f"pr_{n}.json")
        meta = load(SAMPLE / f"pr_{n}_java_meta.json")
        m = metrics[n]
        scored = m["scored"] == "True"
        flagged = scored and m["risk_cat"] in FLAG_CATS
        own_labels = sorted({l["name"] for l in pr["labels"]} & BUG_LABELS)
        paths = {f["path"] for f in meta["java_files"]} | {f["previous_path"] for f in meta["java_files"] if f["previous_path"]}

        hits = []
        if pr["merged_at"]:                      # open PRs: own label only
            for p in sorted(later, key=lambda p: p["number"]):
                if p["created_at"] <= pr["merged_at"]:
                    continue
                files_path = LATER_BUG / f"pr_{p['number']}_files.json"
                if not files_path.exists():
                    sys.exit(f"missing {files_path.relative_to(ROOT)}: run fetch_pr_data.py --group later_bug")
                touched = set()
                for f in load(files_path):
                    for name in (f["filename"], f.get("previous_filename")):
                        if name and name.endswith(".java"):
                            touched.add(name)
                common = sorted(paths & touched)
                if common:
                    hits.append(f"#{p['number']} ({', '.join(common)})")

        evidence = bool(own_labels or hits)
        if not scored:
            outcome = "not scored"
        elif flagged:
            outcome = "correct alarm" if evidence else "false alarm"
        else:
            outcome = "missed high-impact change" if evidence else "correct clear"
        rows.append({
            "pr": n, "state": "merged" if pr["merged_at"] else pr["state"],
            "merged_at": pr["merged_at"] or "", "java_files": len(meta["java_files"]),
            "scored": scored, "risk_score": m["risk_score"], "risk_cat": m["risk_cat"],
            "flagged": flagged, "own_bug_label": "; ".join(own_labels),
            "later_bug_prs_same_java_files": "; ".join(hits),
            "defect_evidence": evidence, "outcome": outcome,
        })
        print(f"#{n}: {'scored ' + m['risk_cat'] if scored else 'NOT SCORED'}  flagged={flagged}  "
              f"evidence={evidence}  -> {outcome}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    counts = {k: sum(r["outcome"] == k for r in rows)
              for k in ("correct alarm", "false alarm", "missed high-impact change", "correct clear", "not scored")}
    print("summary:", ", ".join(f"{k} {v}" for k, v in counts.items()))
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
