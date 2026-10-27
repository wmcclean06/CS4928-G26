## §D Docker run of the recorded pipeline (added 24/10/2026)

This section adds a containerised way to repeat the §2-§4 pipeline. It does not
replace the records in Notes/run_procedure.md: §1-§6 document the original run as executed on
Windows. The Docker route reproduces the same stack - Neo4j 5.3.0 with APOC
5.3.0 and GDS 2.3.2, callgraph-server (Spring Boot 2.6.4 on JDK 8), git and
Python - in one image, built from the same artefact download (CHID_codes.zip,
MD5 2c2212ac3530c5b0940fecd9bb6addfe).

What runs inside the container:

- Neo4j 5.3.0 community (official image) with APOC 5.3.0-core and GDS 2.3.2
  jars baked in; procedures unrestricted/allow-listed for apoc.* and gds.*
  (the server calls gds.graph.*, apoc.do.when and gds.pageRank.write).
- callgraph-server built during `docker build` from the artefact source plus the D5 patch with Maven 3.8.6 on JDK 8 (`mvn -B clean install -DskipTests`, same
  as §2 step 3), then run from /opt/callgraph-server on a pinned Temurin
  JDK 8, so the artefact's clone path resolves to
  /opt/change_impact_detector/analyzed_repositories/arduino/Arduino.
- The artefact source is unmodified except `docker/callgraph-server-linux-path.patch`
  (separator-aware path handling; the artefact hard-codes Windows backslash
  paths and crashes on Linux). Recorded as deviation D5 in
  Notes/deviations.md; the applied patch is kept inside the image at
  /opt/callgraph-server/APPLIED-linux-path.patch.
- git + python3 for the scripts; the project folder is bind-mounted at
  /work, so scripts write into the repo's own data/, results/ and Logs/
  exactly as on Windows, and existing outputs are still never overwritten.

Setup (once):

1. Install Docker Desktop (Windows: WSL2 backend) or any Docker engine.
2. `cp .env.example .env` and fill in GITHUB_TOKEN (read-only fine-grained
   token for public repositories, same role as the recorded system
   environment variable) and the Neo4j password (NEO4J_AUTH and
   NEO4J_PASSWORD must match; at least 8 characters, not 'neo4j').
   .env is git-ignored and excluded from the image.

Commands (from the repo root; helper: `bash docker/run.sh help`):

| Step | Docker command | Replaces |
|---|---|---|
| build image (once) | `bash docker/run.sh build` | §2 steps 1-3 (Neo4j Desktop install, artefact build) |
| start stack | `bash docker/run.sh up` | §2 steps 1+4 (start Neo4j instance, start callgraph-server) |
| check server up | `bash docker/run.sh status` | the "Started CallgraphServerApplication" check |
| §2 step 1 (DB empty) | `bash docker/run.sh shell` then `cypher-shell` -> `MATCH (n) RETURN count(n);` (first start only) | same |
| §2 step 2 create-save | `bash docker/run.sh create-save` | the PowerShell Invoke-RestMethod POST /api/v1/callgraph/create-save |
| §2 step 3 frozen commit | `bash docker/run.sh clone-head` (expect a0df6e0e83b652c72bc78b0a1376c54d6ebc3bee) | git -C <clone> rev-parse HEAD |
| §2 step 4 graph size | `bash docker/run.sh neo4j-stats` (expect 2124 / 3355 / 1701, sum 1.0) | the three MATCH queries in Neo4j Browser |
| §2 collect PR data | `bash docker/run.sh fetch` | `python scripts/fetch_pr_data.py` |
| §3 pilot | `bash docker/run.sh selftest` then `bash docker/run.sh query 8349` and `bash docker/run.sh metrics 8349` | the three §3 commands |
| §4 step 1 fetch PR branches | `bash docker/run.sh fetch-pr-branches` (default 8600 8607 8621 8640 8647; pass others to override) | the git fetch command |
| §4 step 3 all PRs | `bash docker/run.sh query --all` then `bash docker/run.sh metrics --all` | the two §4 commands |
| server log evidence | `bash docker/run.sh save-logs` | redirecting the server window output into Logs/ |

Notes for a Docker run:

- Evidence discipline is unchanged: `create-save` writes
  results/raw/create_save_response_docker_<timestamp>.txt (never overwriting
  the recorded create_save_response.txt), `save-logs` writes
  Logs/callgraph_server_docker_<timestamp>.log, and the scripts keep their
  never-overwrite behaviour.
- Restart equivalence of the 15/10/2026 restart section: `docker run.sh stop`
  / `start` keeps the graph (named volume cs4928_g26_neo4j_data) and the
  clone (named volume cs4928_g26_clone); `bash docker/run.sh neo4j-stats`
  re-checks 2124 functions after a restart.
- The server listens on localhost:8080 inside the container and the scripts
  are run inside the same container, so no script changes were needed.
- Windows hosts run the image through Docker Desktop (Linux containers
  mode, the default). The original unpatched Windows procedure above stays
  the fallback if a fully unmodified artefact is preferred.
- D5 (Linux path patch) is the only artefact change; method, parameters and
  metrics are unaffected.

## Independent Docker verification (27/10/2026)
Fresh clone of the repo in C:\verify with results/raw/callgraph, results/metrics_detail and results/rq1_metrics.csv deleted; separate container and volumes (fresh graph and Arduino clone). Ran build, up, create-save (2124 / 3355 / 1701), clone-head (a0df6e0), fetch-pr-branches, selftest, query --all, metrics --all.
Compared with scripts/compare_runs.py: all requests, PageRank sums (to float precision), impacted methods and edges at levels 1 and 3, the #8600 rejection, and all risk categories and scores match. Anonymous-class method names contain a random ID generated by JavaParser on each graph build, so raw impact files differ in those IDs only; the script normalises them. Output: Logs/docker_verification_27102026.txt.
Setup issue found: Git for Windows checked out docker/cg-entrypoint.sh with Windows line endings, so the container exited (code 127); fixed by converting it to LF and by .gitattributes.