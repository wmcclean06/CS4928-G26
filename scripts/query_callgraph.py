#!/usr/bin/env python3
"""
Lab 4 §3/§4: send sample PRs to the running callgraph-server and save the raw
requests and responses.

For each PR it builds the artefact's PullRequestChange body from
data/raw/sample/pr_<n>_java_meta.json (only the PR's .java files, as in M1
step 1) and calls:
  POST /api/v1/callgraph/pagerank            -> impact size (sum of PageRank of changed methods)
  POST /api/v1/callgraph/impact  level 1     -> directly impacted methods
  POST /api/v1/callgraph/impact  level 3     -> impacted methods up to 3 levels
Saved to results/raw/callgraph/pr_<n>_{request,pagerank,impact_l1,impact_l3}.json.
Existing outputs are never overwritten (use a new run instead).

  python scripts/query_callgraph.py 8349            # one PR (the §3 pilot)
  python scripts/query_callgraph.py --all           # all 10 sample PRs (§4)
"""

import argparse
import csv
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SAMPLE = ROOT / "data" / "raw" / "sample"
OUT = ROOT / "results" / "raw" / "callgraph"
SERVER = "http://localhost:8080/api/v1/callgraph"
STATUS = {"added": "ADDED", "removed": "REMOVED", "modified": "MODIFIED"}


def post(endpoint, body):
    req = urllib.request.Request(f"{SERVER}/{endpoint}", data=json.dumps(body).encode("utf-8"),
                                 headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=3600) as r:
        text = r.read().decode("utf-8")
    return json.loads(text) if text.strip() else None


def build_request(n):
    meta = json.loads((SAMPLE / f"pr_{n}_java_meta.json").read_text(encoding="utf-8"))
    files = []
    for f in meta["java_files"]:
        if f["status"] not in STATUS:
            sys.exit(f"PR #{n}: file {f['path']} has status '{f['status']}', which the "
                     "server does not accept (ADDED/REMOVED/MODIFIED only). Stopping; record this.")
        files.append({
            "fileName": os.path.basename(f["path"]),
            "status": STATUS[f["status"]],
            "oldSha": f["old_sha"] or "",
            "newSha": f["new_sha"] or "",
        })
    return {"prNumber": str(n), "destinationBranchName": "master",
            "projectIdentifier": "arduino/Arduino", "changedFilesWithSha": files}


def run(n):
    targets = {k: OUT / f"pr_{n}_{k}.json" for k in ("request", "pagerank", "impact_l1", "impact_l3")}
    existing = [p.name for p in targets.values() if p.exists()]
    if existing:
        print(f"PR #{n}: outputs already exist ({', '.join(existing)}); skipping, nothing overwritten")
        return
    OUT.mkdir(parents=True, exist_ok=True)
    body = build_request(n)
    targets["request"].write_text(json.dumps(body, indent=1), encoding="utf-8")
    print(f"PR #{n}: {len(body['changedFilesWithSha'])} .java file(s)")

    pagerank = post("pagerank", body)
    targets["pagerank"].write_text(json.dumps(pagerank), encoding="utf-8")
    print(f"  pagerank: {pagerank}")
    for level in (1, 3):
        impact = post("impact", dict(body, impactLevel=level))
        targets[f"impact_l{level}"].write_text(json.dumps(impact, indent=1), encoding="utf-8")
        nodes = (impact or {}).get("nodes", [])
        print(f"  impact level {level}: {sum(1 for x in nodes if x.get('affected'))} impacted, "
              f"{sum(1 for x in nodes if x.get('changed'))} changed method(s) in result")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prs", nargs="*", type=int)
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    if args.all:
        with open(ROOT / "data" / "eligibility_log.csv", newline="", encoding="utf-8-sig") as f:
            prs = [int(r[0]) for r in list(csv.reader(f))[1:] if r and r[-1].startswith("ELIGIBLE")]
    else:
        prs = args.prs
    if not prs:
        sys.exit("give PR numbers or --all")
    for n in prs:
        try:
            run(n)
        except urllib.error.URLError as e:
            print(f"PR #{n}: request failed: {e}. Is callgraph-server running?")


if __name__ == "__main__":
    main()
