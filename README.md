# CS4928-G26

William McClean, Kaiden Foley, Abdulmohsen Alghani

Paper Link: https://link.springer.com/article/10.1007/s10664-024-10600-2

Repository Link: https://doi.org/10.6084/m9.figshare.27643755.v1

Arduino Link https://github.com/arduino/Arduino/tree/a0df6e0e83b652c72bc78b0a1376c54d6ebc3bee

Explanation of the different Metrics used in the paper 

| Metric                         | What it captures                                                                                                                                                                                                                                                                                            | Effect size |
|--------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------|
| Impact Size, 3.2.4             | This attempts to measure the size of the impact graph, quantifying the potential impact of changes at the method leve                                                                                                                                                                                       | 40%         |
| Highly Buggy File, 3.1.2       | If a PR has the label `bug` or `Type: Bug` (the exact labels counted in this reproduction), that PR and the files associated with it are called bug related which then means for a specific file you can figure out it's bug frequency based off the number of bug related PRs it was in over the total number of PRs it was in | 20%         |
| PR Size, 3.1.4                 | This is a scale from A-E for the number of changed lines of code in a PR with [0, 10] being an A while 1000+ is an E                                                                                                                                                                                        | 17.5%       |
| Highly Churned File, 3.1.1     | This is a scale from A-E based upon the [Highly Churned File Ratio for a PR](Notes/Highly%20Churned%20File%20Ratio%20for%20a%20PR.md)                                                                                                                                                                       | 12.5%       |
| Merge Rate, 3.1.5              | This relates to the ratio of the author's merged PRs to the total number of PRs opened by the author                                                                                                                                                                                                        | 10%         |
| Missing Co-change Files, 3.1.3 | Co-change represents the evolutionary coupling between different files, as when any two files  frequently change together in version history, there is a high probability they will change again in the future                                                                                              | 0%          |

#### Thoughts on the above
- Including some scaling factor for Merge rate based off the total PRs for a project 
- The second question would be around picking 5 for a highly churned file as this seems high for certain projects and low for others. So you may be able to again use the lifetime or number of pull requests of a specific project to scale this factor
- For Highly Buggy Files there may be a more rigorous definition of bug which could be used though I understand the difficulty of having to be able to use a metric like this it must be quick to calculate


## Docker quick-start (added 24/10/2026)

The whole stack (Neo4j 5.3.0 + APOC 5.3.0 + GDS 2.3.2, callgraph-server on
JDK 8, git, Python) runs in one container built from this repo:

```bash
cp .env.example .env        # fill in GITHUB_TOKEN and the Neo4j password
bash docker/run.sh build    # downloads the artefact (MD5-checked), patches + builds it
bash docker/run.sh up       # starts Neo4j + callgraph-server, waits for :8080
bash docker/run.sh help     # per-step commands (create-save, neo4j-stats, fetch, query, metrics, ...)
```

The Docker procedure and how each command maps to the recorded §2-§4 steps is
in [Notes/run_procedure_Docker.md](Notes/run_procedure_Docker.md); a guided step-by-step tour with expected outputs and
troubleshooting is in [WALKTHROUGH.md](WALKTHROUGH.md). The only artefact
change is the Linux path patch recorded as D5 in
[Notes/deviations.md](Notes/deviations.md).
