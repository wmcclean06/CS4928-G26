## D1 - 14/10/2026 - Tie rule for RQ2
M1 says high-risk = the top 3 PRs but has no rule for tied scores. If PRs tie at the edge of the top 3 or bottom 3, all tied PRs are included, and the groups are compared by the share with evidence, not the count.

Why: The risk scores are built from whole number categories, so ties are likely. We have set this before any run so we won't be influenced to change it later based on the result we get.. 

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