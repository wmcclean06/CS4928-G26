# Event A result: frozen M2 method on 5 held-out PRs

Plan and prediction (recorded before execution): `Notes/EVENT_A_PLAN.md`, D6, commit 3c83c6f.
Run: Docker route, fresh container `cs4928-g26-eventa`, 27/10/2026. Before scoring, create-save rebuilt the graph and it matched M2 (clone a0df6e0, 2,124 / 3,355 / 1,701, PageRank sum 1.0).
Generated from `results/event_a/event_a_metrics.csv` and `results/event_a/event_a_evidence.csv` (`scripts/event_a_evidence.py`).

## Held-out set and method
First 5 eligible PRs created on or after 01/01/2020 (`data/event_a/eligibility_log.csv`): #9627, #9643, #9644, #9645, #9649. The M2 method was applied unchanged: same scripts, weights, bands and thresholds, with D3 and D4. Nothing was retuned.

## Results

| PR | State | Impact | Buggy | Size | Churn | Merge | Risk | Flagged | Defect evidence | Outcome |
|---|---|---|---|---|---|---|---|---|---|---|
| #9645 | merged | A | **E** | A (7) | A | E | **30.0 B** | yes | none | **false alarm** |
| #9627 | merged | A | A | B (46) | A | C | 9.38 A | no | none | correct clear |
| #9644 | merged | A | A | B (29) | A | C | 9.38 A | no | none | correct clear |
| #9649 | merged | A | A | A (7) | A | D | 7.5 A | no | none | correct clear |
| #9643 | open | – | B | E (103,853) | A | C | **not scored** | – | none | not scored |

#9643 was rejected by the artefact's server (HTTP 400; its request contains one `RENAMED` file; `results/event_a/raw/callgraph/pr_9643_error.json`). This is the same failure as #8600 in M2. Without impact, its other categories already give at least 27.5, so it would be flagged (B or worse) whatever its impact. With no defect evidence, that would make it a second false alarm.

## Decision (plan §3, M1 §5 rule on the held-out set)
- PRs scored: 4 of 5 (at least 4 required) ✓
- Risk categories: A and B (more than one required) ✓

**Event A: TRANSFERS.** On unseen PRs the frozen method still produces a valid ranking that spans more than one category.

**Caveat:** the second category rests on one PR, #9645, whose B comes only from buggy = E (a file with 2 earlier PRs, one bug-labelled). With buggy at A it would score 10.0 (A), leaving all four scored PRs in A, i.e. DOES NOT TRANSFER. As in M2 (#8621), the "more than one category" condition is met by a single, fragile PR.

False alarms: **1** (#9645). Missed high-impact changes: **0**. Correct alarms: 0. Correct clears: 3.
No held-out PR has defect evidence, so a miss or a correct alarm was not possible in this set. "0 misses" says nothing about whether the score detects defects.

## Prediction against outcome

| Prediction (plan §4) | Outcome |
|---|---|
| 1. At least 4 of 5 scored; the only failure would be a renamed file | **Correct.** 4 of 5; #9643 rejected for a renamed file |
| 2. Impact, buggy and churn A for all; merge E for most; flagged only if more than 200 lines | **Wrong.** #9645 (7 lines) was flagged by **buggy = E**. Merge rate was C or D for 3 of 4 scored PRs. Impact and churn were A as predicted |
| 3. Most PRs in A, at most 1–2 flagged | **Correct.** 1 flagged |
| 4. Flags won't line up with defect evidence (at least one false alarm or miss) | **Correct.** 1 false alarm, but through bug frequency, not size |

Challenge conditions (plan §5):
- RQ1 = REPRODUCED: **not challenged** (4 of 5 scored, two categories).
- The M2 "weak discrimination" caveat (ranking driven only by size and merge rate): **partly challenged.** A held-out PR scored above A on buggy and was flagged for that reason.

## Comparison with M2

**What transfers**
- The pipeline runs on a later window and gives a non-degenerate ranking (M2: 9/10, A–B; Event A: 4/5, A–B).
- Impact still contributes nothing. It is A for every scored PR in both sets; the largest Event A PageRank sum is 0.00059, against an A threshold of 0.10.
- Churn is A for every PR in both sets.
- The artefact's renamed-file rejection recurs. Both times it hit the largest PR in the window (#8600, 509 lines; #9643, 103,853 lines).

**What does not transfer**
- The M2 explanation that only size and merge rate move the score. In Event A the only flag comes from the highly-buggy-file metric. Merge rate also varies (C, D and E) instead of being E for every scored PR.
- The M2 second category came from a large first-time-author PR (#8621, size E, D4). The Event A second category comes from a 7-line PR by an established author.

**Strongest evidence:** `results/event_a/metrics_detail/pr_9645.json`. The PR's single file, `DiscoveryManager.java`, has a bug frequency of 0.5 from only 2 earlier PRs: #4792 (labelled `Type: Bug`, 2016) and #8038. One bug-labelled PR from 2016 is enough to cross the 0.4 threshold and make the file "highly buggy". 1 of 1 files is then a buggy ratio of 100%, which is category E. No later bug-labelled PR touches that file.

## Design / maintainability implication
The server's file-status type accepts only ADDED, REMOVED and MODIFIED. GitHub's PR file API also reports `renamed` (and other statuses), and the bot forwards GitHub's status as-is (only upper-cased). The server's interface is therefore coupled to an external vocabulary it does not fully cover, and one unrecognised value rejects the whole request instead of just that file. The consequence is now evidenced twice (#8600, #9643): the largest PRs, which the score would flag, are exactly the ones the tool cannot score. This is a concrete design pressure at the boundary between bot and server. It is a candidate for the Week 9 design decision. Options there include no structural change (report the limitation, as now), or mapping GitHub's statuses at one point on the boundary. No pattern is claimed here.

## Limitations
- Only 4 scored PRs, and none has defect evidence, so false-alarm and miss counts are descriptive only.
- Evidence is label-only (M1). A bug fixed without a label, or under another label, is not counted.
- #9643 is open, so only its own label can count (plan §3).
- The highly-buggy rule has no minimum file history. A file with 2 earlier PRs can be "highly buggy" from a single labelled PR. This follows the artefact (no change made) and is noted as a threat.
