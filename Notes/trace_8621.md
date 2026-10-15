# Trace: #8621 risk score 27.5 (B)

Claim: results/rq1_metrics.csv, row 8621 → risk 27.5, category B (rank 1 of 9 scored).

1. Risk score (compute_metrics.py, risk_score())
   (4×impact 0 + 2×buggy 0 + 1.75×size 4 + 1.25×churn 0 + 1×merge 4) / 10 × 25 = 11 / 10 × 25 = 27.5 → 20–40 band → B

2. Each category, back to its raw evidence
    - Impact A: PageRank sum 0.00111 ≤ 0.10. Raw: results/raw/callgraph/pr_8621_pagerank.json (server response to pr_8621_request.json; server log Logs/callgraph_server_15102026.log).
    - Buggy A: 0 of 3 .java files have bug frequency > 0.4 (highest 0.33, UploaderUtils.java). Per-file values: results/metrics_detail/pr_8621.json, built from data/raw/history/ (468 history PRs used).
    - Size E: 26 additions + 1,106 deletions = 1,132 lines ≥ 1,000. Raw: data/raw/sample/pr_8621.json ("additions", "deletions").
    - Churn A: 0 of 3 .java files have churn > 5 (highest 1.44). Per-file values: results/metrics_detail/pr_8621.json.
    - Merge E: author Pieter12345 has 0 earlier PRs → 0 / (0 + 1) = 0 → E (0–75%). Raw: data/arduino_pr_list.json.

3. Inputs
    - Request sent to the server: results/raw/callgraph/pr_8621_request.json (old/new blob SHAs from data/raw/sample/pr_8621_java_meta.json; new versions fetched into the clone as refs/remotes/origin/pr/8621, see run_procedure.md §4).
    - Call graph built at a0df6e0 (Logs/clone_head.txt, results/raw/callgraph_stats.txt).
    - Selected by the frozen M1 rule: data/eligibility_log.csv row "8621, 08/03/2019, open, 3, ELIGIBLE #7".