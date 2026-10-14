## D1 - 14/10/2026 · Tie rule for RQ2
M1 says high-risk = the top 3 PRs but has no rule for tied scores. If PRs tie at the edge of the top 3 or bottom 3, all tied PRs are included, and the groups are compared by the share with evidence, not the count.

Why: The risk scores are built from whole number categories, so ties are likely. We have set this before any run so we won't be influenced to change it later based on the result we get.. 

Effect: groups may have more than 3 PRs.

## D2 - 14/10/2026 · Neo4j is used
M1 lists "databases" as out of scope, but callgraph-server needs Neo4j to store the call graph and compute PageRank. Neo4j is used only for this. MongoDB and Firebase will stay out of scope.

Why: The impact size can't be computed without it.

Effect: none on the method or metrics. Neo4j is added to the recorded environment.