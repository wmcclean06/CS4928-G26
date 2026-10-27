#!/usr/bin/env python3
"""
Lab 4 §2: collect the raw GitHub data needed for the metrics, without applying
any method rules (filters/thresholds are applied later in the metrics step).

Groups (all read from data/eligibility_log.csv and data/arduino_pr_list.json):
  sample     the 10 ELIGIBLE PRs in data/eligibility_log.csv
  history    merged PRs to master created before the latest sample PR
             (superset of each sample PR's history; per-PR cut-off applied later)
  later_bug  merged PRs labelled "bug" / "Type: Bug" created on/after the
             earliest sample PR (superset of RQ2 "later bug-fix" candidates)

Per PR it saves (data/raw/<group>/):
  pr_<n>.json            GET /pulls/<n>              (sample, history)
  pr_<n>_files.json      GET /pulls/<n>/files        (all groups, all pages)
  pr_<n>_java_meta.json  per .java file: status, blob SHA at base commit (oldSha),
                         blob SHA at head (newSha), non-blank line count at the
                         head commit (as in the bot's getTotalLOC)  (sample, history)
Every request is logged to data/raw/fetch_log.csv. Existing files are skipped,
so the script can be re-run to resume. Requires GITHUB_TOKEN.

  python scripts/fetch_pr_data.py                  # all groups
  python scripts/fetch_pr_data.py --group sample   # one group
  python scripts/fetch_pr_data.py --set event_a     # Event A PRs (data/event_a/eligibility_log.csv
                                                    # -> data/raw/event_a_sample/; history/later_bug shared)
"""

import argparse
import base64
import csv
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

REPO = "arduino/Arduino"
API = "https://api.github.com"
ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
RAW = DATA / "raw"
LOG = RAW / "fetch_log.csv"
BUG_LABELS = {"bug", "Type: Bug"}
# PR set -> (sample list, raw folder for its PRs). history/later_bug are shared;
# per-PR cut-offs are applied in compute_metrics.py.
SETS = {
    "m2":      (DATA / "eligibility_log.csv", "sample"),
    "event_a": (DATA / "event_a" / "eligibility_log.csv", "event_a_sample"),
}


def log(url, status, note=""):
    LOG.parent.mkdir(parents=True, exist_ok=True)
    new = not LOG.exists()
    with open(LOG, "a", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["timestamp_utc", "url", "status", "note"])
        w.writerow([datetime.now(timezone.utc).isoformat(timespec="seconds"), url, status, note])


def get(url):
    """GET a GitHub API URL. Returns parsed JSON, or None on 404."""
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        sys.exit("GITHUB_TOKEN is not set")
    while True:
        req = urllib.request.Request(url, headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
        })
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                log(url, r.status)
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                log(url, 404, "not found")
                return None
            if e.code in (403, 429) and e.headers.get("X-RateLimit-Remaining") == "0":
                reset = int(e.headers.get("X-RateLimit-Reset", time.time() + 60))
                wait = max(reset - time.time(), 0) + 5
                log(url, e.code, f"rate limited, waiting {int(wait)}s")
                print(f"  rate limited, waiting {int(wait)}s ...")
                time.sleep(wait)
                continue
            log(url, e.code, "error")
            raise


def save(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(obj, indent=1), encoding="utf-8")
    tmp.replace(path)


def pr_files(n):
    files, page = [], 1
    while True:
        batch = get(f"{API}/repos/{REPO}/pulls/{n}/files?per_page=100&page={page}")
        files.extend(batch or [])
        if not batch or len(batch) < 100:
            return files
        page += 1


def contents(path, ref):
    """Blob SHA and non-blank line count of a file at a commit (None if absent)."""
    q = urllib.parse.quote(path)
    data = get(f"{API}/repos/{REPO}/contents/{q}?ref={ref}")
    if data is None:
        return {"sha": None, "loc": None, "note": "not found at ref"}
    if data.get("encoding") != "base64" or not data.get("content"):
        return {"sha": data.get("sha"), "loc": None, "note": "content not returned (file > 1 MB?)"}
    # Same counting as the bot's getTotalLOC: decode, split on \n, drop blank lines
    text = base64.b64decode(data["content"]).decode("latin-1")
    loc = sum(1 for line in text.split("\n") if line.strip() != "")
    return {"sha": data["sha"], "loc": loc, "note": ""}


def java_meta(n, pr, files):
    base, head = pr["base"]["sha"], pr["head"]["sha"]
    out = []
    for f in files:
        if not f["filename"].endswith(".java"):
            continue
        old_path = f.get("previous_filename", f["filename"])
        old = contents(old_path, base) if f["status"] != "added" else {"sha": None, "loc": None, "note": "added"}
        new = contents(f["filename"], head) if f["status"] != "removed" else {"sha": None, "loc": None, "note": "removed"}
        out.append({
            "path": f["filename"], "previous_path": f.get("previous_filename"),
            "status": f["status"], "additions": f["additions"], "deletions": f["deletions"],
            "old_sha": old["sha"], "new_sha": f["sha"],
            "head_sha_check": new["sha"], "loc_at_head": new["loc"],
            "notes": "; ".join(x for x in (old["note"], new["note"]) if x),
        })
    return {"pr": n, "base_sha": base, "head_sha": head, "java_files": out}


def fetch(group, numbers, with_meta):
    folder = RAW / group
    for i, n in enumerate(numbers, 1):
        f_pr, f_files, f_meta = (folder / f"pr_{n}.json", folder / f"pr_{n}_files.json",
                                 folder / f"pr_{n}_java_meta.json")
        need = [f_files] + ([f_pr, f_meta] if with_meta else [])
        if all(p.exists() for p in need):
            continue
        print(f"[{group}] {i}/{len(numbers)} PR #{n}")
        pr = None
        if with_meta:
            pr = get(f"{API}/repos/{REPO}/pulls/{n}")
            save(f_pr, pr)
        files = pr_files(n)
        save(f_files, files)
        if with_meta:
            if any(f["filename"].endswith(".java") for f in files):
                save(f_meta, java_meta(n, pr, files))
            else:
                save(f_meta, {"pr": n, "base_sha": pr["base"]["sha"],
                              "head_sha": pr["head"]["sha"], "java_files": []})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--group", choices=["sample", "history", "later_bug", "all"], default="all")
    ap.add_argument("--set", choices=list(SETS), default="m2")
    args = ap.parse_args()

    elig, sample_dir = SETS[args.set]
    with open(elig, newline="", encoding="utf-8-sig") as f:
        rows = list(csv.reader(f))[1:]
    sample = [int(r[0]) for r in rows if r and r[-1].startswith("ELIGIBLE")]
    prs = {p["number"]: p for p in json.loads((DATA / "arduino_pr_list.json").read_text(encoding="utf-8"))}
    first = min(prs[n]["created_at"] for n in sample)
    last = max(prs[n]["created_at"] for n in sample)

    history = sorted(n for n, p in prs.items() if p["merged_at"] and p["created_at"] < last)
    later_bug = sorted(n for n, p in prs.items()
                       if p["merged_at"] and p["created_at"] >= first
                       and BUG_LABELS & set(p["labels"]))
    print(f"sample {len(sample)}, history {len(history)}, later_bug {len(later_bug)}")

    if args.group in ("sample", "all"):
        fetch(sample_dir, sample, True)
    if args.group in ("history", "all"):
        fetch("history", history, True)
    if args.group in ("later_bug", "all"):
        fetch("later_bug", later_bug, False)
    print("done")


if __name__ == "__main__":
    main()
