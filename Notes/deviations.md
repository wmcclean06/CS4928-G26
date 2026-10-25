## D1 - 14/10/2026 - Tie rule for RQ2
M1 says high-risk = the top 3 PRs but has no rule for tied scores. If PRs tie at the edge of the top 3 or bottom 3, all tied PRs are included, and the groups are compared by the share with evidence, not the count.

Why: The risk scores are built from whole number categories, so ties are likely. We have set this before any run so we won't be influenced to change it later based on the result we get. 

Effect: groups may have more than 3 PRs.

## D2 - 14/10/2026 - Neo4j is used
M1 lists "databases" as out of scope, but callgraph-server needs Neo4j to store the call graph and compute PageRank. Neo4j is used only for this. MongoDB and Firebase will stay out of scope.

Why: The impact size can't be computed without it.

Effect: none on the method or metrics. Neo4j is added to the recorded environment.

## D3 - 15/10/2026 - When a history PR counts as merged
M1 says history = PRs created before each PR, but not when they had to be merged. A history PR only counts as merged if it was merged before the sampled PR was created. This applies to churn, bug frequency and author merge rate.

Why: this is the information CHID would have had when the PR was opened. Set before any metrics were computed.

Effect: PRs merged after the sampled PR was opened are not counted, so history is slightly smaller.

## D4 - 15/10/2026 - Author merge rate for a first-time author (disclosure)
compute_metrics.py applies the bot's formula merged / (earlier PRs + 1), so an author with no earlier PRs gets 0 → category E. This matches the bot's historical analysis. The bot's live mode would instead leave the category unset (no database record for the author), so the PR would not be scored.

When: the rule was in the script before the §4 run; its effect was identified afterwards, while tracing #8621 (15/10/2026). Nothing was changed after seeing results.

Effect: only #8621 is affected. With the formula: 9/10 scored, categories A and B. With the bot's live behaviour: 8/10 scored, all A. Both are reported.


## D5 - 24/10/2026 - Linux path patch for the Docker image
The artefact's callgraph-server builds file paths with Windows backslash
logic: e.g. `currentPath.substring(0, currentPath.lastIndexOf("\\"))` and
`upperLevelPath + "\\" + "change_impact_detector..."`. On Linux
`lastIndexOf("\\")` returns -1, so create-save (and the folderPath computed
in the pagerank/impact handlers) throws StringIndexOutOfBoundsException and
the endpoints fail. The Docker image therefore applies
docker/callgraph-server-linux-path.patch (10 lines across CallGraphService.java
and CallgraphUtils.java): separator-aware parent lookup
(`Math.max(lastIndexOf("\\"), lastIndexOf("/"))`) and File.separator joins.
No analysis, parameter or metric logic is touched; git is invoked through the
artefact's existing sh branch, which is unchanged.

When: added with the Docker image on 24/10/2026, after the original §1-§6
run; the original run's evidence is untouched and the Windows procedure
remains executable unpatched.

Effect: none on the original run (it was executed unpatched on Windows). For
Docker re-runs: same behaviour, Linux-compatible paths; the diff temp folder
the server writes git-show files into lands beside the clone instead of in
analyzed_repositories, which has no effect on any metric. The applied patch
is stored inside the image at /opt/callgraph-server/APPLIED-linux-path.patch
as evidence of exactly what was applied.

## D6 - 25/10/2026 - apt pinned to archive.debian.org in the image build
The image's two apt stages (artefact-prep on debian:bullseye-slim, and the
runtime stage on neo4j:5.3.0, which is Debian 11 based) originally used the
regular deb.debian.org mirrors with a fallback to archive.debian.org that
only triggered if `apt-get update` itself failed. Debian 11 reached
end-of-life on 31/08/2026: its suites are frozen and moved to
archive.debian.org, while the regular mirrors still serve a bullseye-security
package index whose .deb files are progressively removed from the pool. The
result is the failure mode observed in the first Windows build on 25/10/2026:
`apt-get update` succeeds, then `apt-get install` 404s on the security
packages (openssl, ca-certificates, curl, libcurl4, libnghttp2-14, unzip).
The Dockerfile now rewrites /etc/apt/sources.list to archive.debian.org
unconditionally in both stages. Plain HTTP is used because the artefact-prep
stage has no ca-certificates before the install; package integrity is
guaranteed by apt's signature verification regardless of transport.
Verified on 25/10/2026: archive.debian.org serves all three bullseye suites
(bullseye, bullseye-updates, bullseye-security) and the exact package
versions the 404s hit, and neither suite declares Valid-Until (no
"Release file expired" errors). None of the apt packages in either stage is
part of the studied stack: they are build tools (curl/unzip/patch) and
runtime utilities (git/python3/procps).
When: added 25/10/2026 after the first Windows Docker build failed at
artefact-prep step 2/6; changes only the image build, not the recorded
environment or any recorded step.
Effect: none on any recorded result. The apt package versions installed are
the final Debian 11 LTS versions from the frozen archive, which is more
deterministic than the previous live-mirror behaviour. Documented in
Notes/environment.md (Docker table) and WALKTHROUGH.md section 2.