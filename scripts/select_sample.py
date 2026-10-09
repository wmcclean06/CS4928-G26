#!/usr/bin/env python3
"""
Applies the frozen selection rule:
  - Candidates: PRs to `master` created on or after 01/01/2019.
  - Eligible:   merged or open (closed-unmerged excluded), and at least one
                .java file with GitHub status "modified"
  - Order:      ascending PR number; take the first N eligible.

Outputs (in data/):
  arduino_pr_list.json  - all PRs to master (raw metadata from the GitHub API)
  eligibility_log.csv   - every candidate checked, with the decision and reason

  python scripts/select_sample.py                     # fetch PR list from GitHub, then select
  python scripts/select_sample.py --use-cached-list   # reuse data/arduino_pr_list.json
  python scripts/select_sample.py --use-cached-list --out rerun/   # re-run into another folder to compare
"""

import argparse
import csv
import json
import os
import urllib.request
from pathlib import Path

REPO = "arduino/Arduino"
BASE = "master"
API = "https://api.github.com"
DATA = Path(__file__).resolve().parent.parent / "data"


def get(url):
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def fetch_pr_list():
    prs, page = [], 1
    while True:
        batch = get(f"{API}/repos/{REPO}/pulls?state=all&base={BASE}"
                    f"&per_page=100&page={page}&sort=created&direction=asc")
        if not batch:
            break
        for p in batch:
            prs.append({
                "number": p["number"],
                "created_at": p["created_at"],
                "merged_at": p["merged_at"],
                "state": p["state"],
                "base": p["base"]["ref"],
                "user": (p["user"] or {}).get("login"),
                "labels": [l["name"] for l in p["labels"]],
            })
        if len(batch) < 100:
            break
        page += 1
    return prs


def modified_java_files(number):
    files, page = [], 1
    while True:
        batch = get(f"{API}/repos/{REPO}/pulls/{number}/files?per_page=100&page={page}")
        files.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return [f["filename"] for f in files
            if f["filename"].endswith(".java") and f["status"] == "modified"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cutoff", default="2019-01-01", help="candidates created on/after this date")
    ap.add_argument("--n", type=int, default=10, help="sample size")
    ap.add_argument("--use-cached-list", action="store_true",
                    help="read data/arduino_pr_list.json instead of re-fetching")
    ap.add_argument("--out", default=str(DATA),
                    help="output folder (default: data/); use another folder to re-run and compare")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    if args.use_cached_list:
        prs = json.loads((DATA / "arduino_pr_list.json").read_text())
    else:
        prs = fetch_pr_list()
        (out / "arduino_pr_list.json").write_text(json.dumps(prs, indent=1))
    print(f"{len(prs)} PRs to {BASE}")

    candidates = sorted((p for p in prs if p["created_at"][:10] >= args.cutoff),
                        key=lambda p: p["number"])
    log, selected = [], []
    for p in candidates:
        n, created = p["number"], p["created_at"][:10]
        if not (p["merged_at"] or p["state"] == "open"):
            log.append([n, created, "closed-unmerged", "", "excluded: not merged/open"])
            continue
        state = "merged" if p["merged_at"] else "open"
        java = modified_java_files(n)
        if java:
            selected.append(n)
            log.append([n, created, state, len(java), f"ELIGIBLE #{len(selected)}"])
        else:
            log.append([n, created, state, 0, "excluded: no modified .java file"])
        if len(selected) == args.n:
            break

    with open(out / "eligibility_log.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["pr", "created", "state", "modified_java_files", "decision"])
        w.writerows(log)

    if len(selected) < args.n:
        print(f"WARNING: only {len(selected)} eligible PRs found (rule: use all, record this)")
    print("Selected:", ", ".join(f"#{n}" for n in selected))


if __name__ == "__main__":
    main()
