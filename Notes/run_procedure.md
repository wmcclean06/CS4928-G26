# Run procedure

## §2 - Preparing for the traceable run: environment (14/10/2026)
1. Neo4j Desktop 2.2.1: created a local instance on Neo4j 5.3.0 with the APOC 5.3.0 and Graph Data Science 2.3.2 plugins (APOC was installed on the correct version automatically through Neo4J desktop and GDS can be found here: https://github.com/neo4j/graph-data-science/releases/tag/2.3.2. Started the instance.
2. callgraph-server used from Desktop\27643755\CHID_codes\callgraph-server, unmodified except src\main\resources\application.properties to configure the neo4J URI and password.
3. Build callgraph-server (JDK 1.8.0_202), run from PowerShell:
   cmd /c "cd /d ""...\27643755\CHID_codes\callgraph-server"" && mvnw.cmd -B clean install -DskipTests > ""...\CS4928-G26\Logs\callgraph_build_14-10-2026.log"" 2>&1"
    - Compiles the server with Maven, skipping its tests.
    - All output is written to Logs/callgraph_build_14-10-2026.log, which ends in BUILD SUCCESS.
4. Start callgraph-server, run from a separate PowerShell window that stays open:
   cmd /c "cd /d ""...\27643755\CHID_codes\callgraph-server"" && mvnw.cmd spring-boot:run > ""...\CS4928-G26\Logs\callgraph_server_14102026.log"" 2>&1"
    - Starts the server on http://localhost:8080. It keeps running until the window is closed.
    - All output is written to Logs/callgraph_server_14102026.log, which shows "Started CallgraphServerApplication".
5. GitHub access: read-only fine-grained token for public repositories, stored in the GITHUB_TOKEN system environment variable (not recorded).

## §2 - Preparing for the traceable run: call graph at the frozen commit (14/10/2026) 
1. Checked the Neo4j database was empty in Neo4j Browser: `MATCH (n) RETURN count(n)` returned 0.

2. In a new PowerShell window, from the repo root:

```powershell
$body = @{ projectIdentifier = "arduino/Arduino"; branchName = "master"; githubToken = $env:GITHUB_TOKEN } | ConvertTo-Json
$response = Invoke-RestMethod -Method Post -Uri "http://localhost:8080/api/v1/callgraph/create-save" -ContentType "application/json" -Body $body -TimeoutSec 0
$response | Out-File -Encoding utf8 results\raw\create_save_response.txt
```

- The server clones arduino/Arduino, builds the call graph from every .java file, stores it in Neo4j and runs PageRank.
- Clone location: `...\27643755\CHID_codes\change_impact_detector\analyzed_repositories\arduino\Arduino`
- The response (the clone path) is saved in `results/raw/create_save_response.txt`. An empty response would have meant failure.
- Server output is in `Logs/callgraph_server_14102026.log`. The line "fatal: not a git repository ... code 128" after the clone comes from the artefact's Gradle clean-up step (`git reset --hard` in `CallgraphUtils.downloadDependencyJars`), which runs in the parent folder instead of the clone. Arduino has no Gradle or Maven files, so there was nothing to reset, and the checkout/pull that followed succeeded.

3. Confirmed the frozen commit:

```powershell
git -C "...\27643755\CHID_codes\change_impact_detector\analyzed_repositories\arduino\Arduino" rev-parse HEAD | Out-File -Encoding utf8 Logs\clone_head.txt
```

- Result: a0df6e0e83b652c72bc78b0a1376c54d6ebc3bee (matches M1).

4. Recorded the graph size in Neo4j Browser and saved it to `results/raw/callgraph_stats.txt`:

```cypher
MATCH (f:Function) RETURN count(f) AS functions;
MATCH ()-[r:CALLS]->() RETURN count(r) AS calls;
MATCH (f:Function) WHERE f.pagerank IS NOT NULL RETURN count(f) AS withPagerank, sum(f.pagerank) AS pagerankSum;
```

- Results: 2,124 functions, 3,355 calls, 1,701 with PageRank, PageRank sum 1.0 (confirms PageRank ran with the artefact's normalisation).

## §2 Prepare the run: collect PR data (14/10/2026)
```powershell
python scripts/fetch_pr_data.py
```
- Fetches raw GitHub data for the 10 sample PRs, the 474 merged PRs created before the last sample PR (history), and the 11 later merged bug-labelled PRs (RQ2), into data/raw/. No method rules are applied at this stage.
- Every request is logged in data/raw/fetch_log.csv.
- - data/raw/later_bug/ is collected for RQ2 later in the semester and is not used in the M2 (RQ1) result.

Status 14/10/2026: IN PROGRESS. §1–§2 complete (environment, call graph at a0df6e0, raw PR data). Next: §3 pilot on #8349 (write metrics script, check against Fig. 10).

## Restart (15/10/2026)
- Started the Neo4j instance; graph still present (MATCH (f:Function) RETURN count(f) → 2124). 
- Started callgraph-server with the same command as before, logging to Logs/callgraph_server_15102026.log.

## §3 Prove the pipeline: pilot on #8349 (15/10/2026)
```powershell
python scripts/query_callgraph.py 8349
python scripts/compute_metrics.py 8349
```
- query_callgraph.py sent #8349's .java files (Base.java) to callgraph-server and saved the request and responses to results/raw/callgraph/pr_8349_*.json.
- Changed method: Base.handleClose(Editor), matching the PR diff. Impacted methods: 5 at level 1, 7 at level 3. PageRank sum 0.000666.
- compute_metrics.py: Fig. 10 self-test PASS (44.38, C). #8349 categories: impact A, buggy A, size A, churn A, merge E → risk 10.0, A. Output in results/rq1_metrics.csv and results/metrics_detail/pr_8349.json.
- Churn and buggy ratios use only the PR's .java files (M1 step 1). Affects #8429 (1 of 5 files) and #8621 (3 of 31 files); the bot's live mode would count all files.
- Pipeline confirmed valid on one PR. No method changes needed after the pilot.

## §4 Run the bounded reproduction (15/10/2026)
1. Fetched the PR branches whose new file versions were missing from the server's clone (open PRs plus one file in #8600). Execution repair only: the clone stays on master @ a0df6e0 and the call graph is unchanged.
```powershell
git -C "<clone location>" fetch origin "+refs/pull/8600/head:refs/remotes/origin/pr/8600" "+refs/pull/8607/head:refs/remotes/origin/pr/8607" "+refs/pull/8621/head:refs/remotes/origin/pr/8621" "+refs/pull/8640/head:refs/remotes/origin/pr/8640" "+refs/pull/8647/head:refs/remotes/origin/pr/8647"
```
- Checked afterwards: all old/new file versions for the 10 PRs present; each fetched branch matches the head SHA in data/raw/sample; clone HEAD still a0df6e0.
2. #8600 contains a renamed file. It is sent with status RENAMED, as the bot does; the artefact's server only accepts ADDED/REMOVED/MODIFIED, so it is expected to reject the PR. The rejection is kept as evidence and #8600 is reported as NOT SCORED (artefact limitation, no deviation).
3. Queried the server for all sample PRs and computed the metrics:
```powershell
python scripts/query_callgraph.py --all
python scripts/compute_metrics.py --all
```
- #8349 skipped (pilot outputs already existed; nothing overwritten).
- #8600 rejected by the server (HTTP 400; server log: cannot deserialize FileStatus "RENAMED"). Evidence in results/raw/callgraph/pr_8600_error.json. Reported as NOT SCORED.
- #8640: PageRank 0.0003 but 0 changed methods in the impact results; its changed methods have no callers, and the impact query only returns changed methods that do.
- #8647: PageRank 0.0. Its only changed existing method is the Base(String[]) constructor (UIHelper.java is a new file, which the server skips); the constructor contributes no PageRank. Artefact behaviour, not a failure.
- Results: 9 of 10 PRs scored. Risk scores: #8621 27.5 (B); #8607 and #8647 18.75 (A); #8429, #8458, #8537, #8638 and #8640 14.37 (A); #8349 10.0 (A); #8600 not scored. Full values in results/rq1_metrics.csv; per-file values in results/metrics_detail/.

Status 15/10/2026: IN PROGRESS. §1–§4 complete: bounded run done, 9/10 PRs scored, #8600 not scored (artefact rejects renamed files). Next: §5 results table, §6 apply decision rules.

## §5 Evidence chain (15/10/2026)
- Traced #8621 (risk 27.5, B; the only PR above category A) from results/rq1_metrics.csv back to the raw server response, raw GitHub data, file versions in the clone, the frozen commit and its eligibility log entry. Full trace: Notes/trace_8621.md.
- Each step was re-checked independently against the raw data and all values matched.
- The trace showed that #8621's merge-rate category depends on how a first-time author is handled, which decides the RQ1 outcome. Recorded as D4 (disclosure; nothing changed after the run).

## §6 Compare with the original study (15/10/2026)
- Applied the M1 RQ1 decision rule to results/rq1_metrics.csv: 9/10 PRs scored, risk categories A and B → REPRODUCED.
- Result, ranking and caveats (including D4) in results/rq1_result.md.

Status 15/10/2026 (after §6): RQ1 REPRODUCED under the run as executed; NOT REPRODUCED under the bot's live handling of first-time authors (D4). Evidence: results/rq1_result.md, results/rq1_metrics.csv, Notes/trace_8621.md.