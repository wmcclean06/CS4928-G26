# M1_PLAN

**G26** William McClean, Kaiden Foley, Abdulmohsen Alghani

---

## 1 · Assigned Study & Resources

| Item | Value                                                                                                                                                                                       |
|---|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Assigned study | Göçmen, Cezayir & Tüzün, "Enhanced code reviews using pull request based change impact analysis", *Empirical Software Engineering* 30:64 (2025). https://doi.org/10.1007/s10664-024-10600-2 |
| Artefact | CHID replication package, https://doi.org/10.6084/m9.figshare.27643755.v1 (accessed 09/10/2026)                                                                                             |
| Project pack | P26: Pull-Request Change Impact for Code Review                                                                                                                                             |


---

## 2 · Freezing the Research Questions and target results

| Freeze item | Recorded                                                                                                                                                                                           |
|---|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **RQ(s)** | **RQ1.** Can PR-level change-impact ranking be reproduced on the selected project?<br>**RQ2.** Which high-risk predictions correspond to real review/defect evidence?                              |
| **Source anchor** | **RQ1:** Paper §3.1, §3.2.3-3.2.4, §3.3 (Tables 3–7, Fig. 8), §4.2.2, Fig. 10.<br>**RQ2:** Paper §3.3 and Table 1: the risk score estimates "the likelihood of a pull request causing bugs or issues", §3.1.2. |
| **Target result** | **RQ1:** For each sampled PR: changed files, directly impacted methods (1 level) and impacted methods up to 3 levels (§3.2.3), history/risk metrics and a risk score, giving a ranking of the PRs.<br>**RQ2:** For each high-risk prediction (the 3 highest-ranked PRs), whether it has real review or defect evidence. |
| **Out of scope** | Focus groups and surveys, GitHub bot, web app and databases, execution-time experiments, projects other than Arduino                                                                               |

---

## 3 · Bounding the sample

| Sample Element       | Freezing now                                                                                                                                                                                                                 |
|----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Unit of analysis** | One pull request (PR).                                                                                                                                                                                                       |
| **Source/version**   | https://github.com/arduino/Arduino, branch `master`, commit "TODO". Arduino is one of the paper's evaluation projects (Table 10).                                                                                            |
| **Size/range**       | 10 PRs: "TODO: 10 PR numbers"                                                                                                                                                                                                |
| **Selection rule**   | First 10 eligible PRs in ascending PR number, created on or after "TODO: cutoff date". Eligible = merged or open, base `master`, changes at least one existing `.java` file (paper §4.2.1–4.2.2).|

---

## 4 · Freeze the method, metric and evidence route

| INPUTS                                                                                                                                                                                               | PROCEDURE | OUTPUT / DECISION                                                                                                                                                                                                                     |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Arduino repository at the frozen commit.<br><br>PR data from GitHub: changed files, lines changed, labels, author, merged state.<br><br>For each PR, only PRs created before it are used as history. | 1. List the changed `.java` files.<br>2. Build the method call graph and find changed methods using the artefact's `callgraph-server` code.<br>3. Impacted methods = callers of changed methods: direct callers (1 level, per project pack) and up to 3 levels (per paper §3.2.3).<br>4. Compute the metrics with the paper's definitions and thresholds: impact size (PageRank), highly churned file ratio, highly buggy file ratio, PR size, author merge rate (§3.1, Tables 3–7).<br>5. Risk score = weighted sum with the artefact's default weights: impact 4, buggy 2, size 1.75, churn 1.25, merge rate 1 (Fig. 8; `github-bot/models/Repository.js`).<br>6. Rank the 10 PRs by risk score. | **RQ1:** a table of the 10 PRs with metrics, risk score and rank.<br><br>**RQ2:** for each PR, whether review/defect evidence exists (bug label, or a later bug-fix PR touching the same files). List each high-risk prediction (top 3) with its evidence; compare with the bottom 3. |

**Bounded decisions where the source does not specify:**
- Bug-related PR = labelled `Type: Bug` / `bug`.
- Category values follow the artefact code (0–4).
- High-risk prediction = the 3 highest-ranked PRs by risk score.
---

## 5 · Pre-declare the expected result and decision rule

**Expected result:** all metrics and a risk score can be computed for every PR, giving a ranking that separates the PRs. The top-ranked PRs will show more review/defect evidence than the bottom-ranked ones.

| Outcome | Our criterion                                                                                                                       |
|---|-------------------------------------------------------------------------------------------------------------------------------------|
| **REPRODUCED** | A risk score is computed per the paper's definitions for at least 8 of 10 PRs, and the scores fall into more than one risk category. |
| **NOT REPRODUCED** | A valid run completes, but fewer than 8 PRs can be scored, or all scores fall into one category.                                    |
| **INCONCLUSIVE / BLOCKED** | Build, data or environment problems prevent a valid run.                                                                            |

RQ2 is reported descriptively: the evidence count for the top 3 vs bottom 3.

---

## 6 · Run a feasibility check

| Check                                            | Result / evidence                                               |
|--------------------------------------------------|-----------------------------------------------------------------|
| Arduino repo accessible; default branch `master` | Confirmed via GitHub, 09/10/2026                                |
| `Type: Bug` label exists                         | Confirmed via GitHub, 09/10/2026                                |
| Artefact downloads and unpacks                   | `CHID_codes.zip` contains `callgraph-server/` (Java 1.8, Maven) |
| First essential step: `callgraph-server` builds  |                                                                 |
| Blockers                                         |                                                                 |

---

## 7 · Freeze M1, then begin the reproduction

Once marked READY, this file is frozen and tagged `M1_PLAN`. Any later change is recorded as a deviation (what changed, why, and how it affects interpretation) rather than edited here.
