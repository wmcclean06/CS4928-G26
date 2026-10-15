# RQ1 result: Can PR-level change-impact ranking be reproduced on the selected project?

Sample: 10 PRs from arduino/Arduino (M1 §3). Generated from results/rq1_metrics.csv (15/10/2026).

| Rank | PR | State | Impact | Buggy | Size | Churn | Merge | Risk | Risk cat. |
|---|---|---|---|---|---|---|---|---|---|
| 1 | #8621 | open | A | A | E | A | E | 27.5 | B |
| 2= | #8607 | open | A | A | C | A | E | 18.75 | A |
| 2= | #8647 | open | A | A | C | A | E | 18.75 | A |
| 4= | #8429 | merged | A | A | B | A | E | 14.37 | A |
| 4= | #8458 | merged | A | A | B | A | E | 14.37 | A |
| 4= | #8537 | merged | A | A | B | A | E | 14.37 | A |
| 4= | #8638 | merged | A | A | B | A | E | 14.37 | A |
| 4= | #8640 | open | A | A | B | A | E | 14.37 | A |
| 9 | #8349 | merged | A | A | A | A | E | 10.0 | A |
| – | #8600 | merged | – | A | D | A | D | not scored | – |

#8600 was rejected by the artefact's server (renamed file; results/raw/callgraph/pr_8600_error.json).

## Decision (M1 §5 rule)
Run validity: valid and complete. All 10 PRs attempted; one artefact rejection, kept as evidence.
- PRs scored: 9 of 10 (at least 8 required) ✓
- Risk categories: A and B (more than one required) ✓

**RQ1: REPRODUCED**: the method re-runs on Arduino and produces a valid, non-degenerate ranking.

## Caveats
1. D4: the result depends on how a first-time author's merge rate is handled. Under the bot's live behaviour, #8621 would not be scored, leaving 8 PRs all in category A → NOT REPRODUCED.
2. Weak discrimination: impact, churn and buggy are category A for every scored PR, so the ranking is driven by PR size and author merge rate. Only one PR reaches B.
3. Impact sizes are tiny (largest PageRank sum 0.0095, #8607, against an A threshold of 0.10). The call graph is small (2,124 methods), possibly because dependency code is not resolved for an Ant-built project.
4. The paper publishes no per-PR ranking, so "reproduced" means the method re-runs and ranks, not that it matches published numbers (M1 §5).
