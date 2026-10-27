# EVENT_A_PLAN: pre-registration (written before any Event A analysis)

**G26** William McClean, Kaiden Foley, Abdulmohsen Alghani · Recorded 27/10/2026

Pre-event state: tag `PRE_EVENT_A` (c29b4b8). The M2 result (`results/rq1_result.md`) is not changed by Event A.

---

## 1 · Held-out material

| Item | Recorded |
|---|---|
| Project / version | arduino/Arduino `master` @ a0df6e0e83b652c72bc78b0a1376c54d6ebc3bee, the same as M2. Same call graph (Neo4j instance CS4928G26, 2,124 methods) |
| PR list | `data/arduino_pr_list.json`, the cached list used in M2 (not re-fetched) |
| Window | First 5 eligible PRs created on or after **01/01/2020** (no overlap with the M2 window 02/01/2019–12/03/2019) |
| Eligibility / order | Unchanged from M1 §3: base `master`, merged or open, at least one `.java` file with status "modified", ascending PR number |
| Command | `python scripts/select_sample.py --use-cached-list --cutoff 2020-01-01 --n 5 --out data/event_a` |
| Held-out PRs | #9627, #9643, #9644, #9645, #9649 (log: `data/event_a/eligibility_log.csv`) |

## 2 · Frozen method (applied unchanged, no retuning)

M1 §4 and M2 exactly: the same scripts, the artefact's weights (4 / 2 / 1.75 / 1.25 / 1), the category bands, the `>` thresholds (churn > 5, bug frequency > 0.4) and the label-only bug definition. Deviations D3 (history = PRs created **and merged** before each held-out PR was opened) and D4 (first-time author → merge E) apply as in M2. M2 outputs are not overwritten; Event A outputs go to separate files.

## 3 · Event A decision rules (see D6)

| Term | Definition |
|---|---|
| **Scored** | A risk score is computed for the PR. Same 80% bar as M1: at least **4 of 5** |
| **Flagged (high risk)** | Risk category **B or worse** (score > 20) |
| **Defect evidence** | M1 RQ2 rule: the PR has a `bug` / `Type: Bug` label, **or** a later merged PR with that label touches at least one of the same `.java` files. "Later" = created after the held-out PR was merged. For open PRs, only the label counts |
| **False alarm** | Flagged, with no defect evidence |
| **Missed high-impact change** | Not flagged, with defect evidence |
| **Transfer of the M2 result** | The M1 §5 RQ1 rule on the held-out set: at least 4 of 5 scored **and** scores in more than one risk category |

## 4 · Prediction (before execution)

Basis: the M2 metrics (`results/rq1_metrics.csv`). Impact, buggy and churn were A for every PR. Merge rate was E for every scored PR, because Arduino merges a low share of PRs. So in practice risk ≈ 10 + 4.375 × size category.

1. **Scoring:** at least 4 of 5 are scored. The only expected failure is a PR that renames a `.java` file (HTTP 400, as with #8600).
2. **Metrics:** impact, buggy and churn are A for all 5, and merge rate is E for most. A PR is therefore flagged only if it changes **more than 200 lines** (size D or E).
3. **Ranking:** most PRs fall in category A, and at most 1–2 are flagged. Whether more than one category appears depends on whether a PR of more than 200 lines is drawn, not on change impact.
4. **False alarms / misses:** flags will not line up with defect evidence. We expect at least one false alarm or miss, and any PR with defect evidence of 200 lines or fewer will be missed.

## 5 · What would challenge the M2 conclusion

- **Against RQ1 = REPRODUCED:** fewer than 4 of 5 scored, or all scored PRs in one category (the ranking degenerates on unseen PRs).
- **Against the M2 "weak discrimination" caveat:** any held-out PR with impact, buggy or churn above A, or a flag that is not explained by size and merge rate.
