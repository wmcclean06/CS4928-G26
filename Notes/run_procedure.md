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