# CS4928-G26 — Docker walkthrough

A step-by-step guide to repeating the recorded CHID reproduction pipeline
(§2–§4 of `Notes/run_procedure.md`) in one Docker container — from a fresh
clone of this repository to the reproduced risk scores in
`results/rq1_metrics.csv`.

At the end you will have:

- a running stack of Neo4j 5.3.0 + APOC 5.3.0 + GDS 2.3.2 + callgraph-server
  (Spring Boot 2.6.4 on JDK 8) in one container;
- the Arduino call graph at the frozen commit `a0df6e0` in Neo4j
  (2,124 functions / 3,355 CALLS / 1,701 with PageRank, sum 1.0);
- raw PR data, impact queries and metric outputs for the 10 sample PRs,
  written into this repository's `data/`, `results/` and `Logs/` folders
  exactly as on the original Windows run;
- 9/10 PRs scored (same as the recorded §4 run) → RQ1 REPRODUCED.

Everything here is the tutorial companion to the authoritative records:

| Record | What it holds |
|---|---|
| `Notes/run_procedure.md` §1–§6 | The original run as executed on Windows (unchanged) |
| `Notes/run_procedure.md` §D | The terse Docker command table this walkthrough expands |
| `Notes/deviations.md` | D1–D5; **D5** is the only artefact change in the image |
| `Notes/environment.md` | Software versions, original and Docker |

Rough timings on a typical laptop/connection: image build 5–15 min (once),
stack start ~1–2 min, `create-save` a few minutes, the rest is minutes.
Allow ~30–45 minutes end to end plus download time.

---

## 0. Before you start

You need:

1. **Docker** — Docker Desktop (Windows: WSL2 backend; macOS) or a Docker
   Engine on Linux. The image is built for `linux/amd64`; on Apple Silicon
   enable Rosetta x86 emulation (see [Troubleshooting](#11-troubleshooting)).
2. **bash or PowerShell** — macOS/Linux (and Git Bash/WSL on Windows) run
   `docker/run.sh`; on Windows you can instead drive everything from the
   preinstalled PowerShell with `docker\run.ps1` — no bash needed (see the
   Windows PowerShell note in §13).
3. **A GitHub token** — read-only fine-grained token for public
   repositories. This plays the same role as the `GITHUB_TOKEN` system
   environment variable recorded in §2. It is used to clone `arduino/Arduino`
   and to fetch PR data. (Never commit it; `.env` is git-ignored.)
4. **Internet access** during the build — figshare (the artefact), Docker
   Hub, Maven Central, GitHub releases (plugins, JDK 8), Debian mirrors.
5. **Disk space** — roughly 3–4 GB free (image ~1.5 GB plus the graph,
   its logs and the Arduino clone in named volumes).

---

## 1. Configure `.env`

From the repository root:

```bash
cp .env.example .env
```

Open `.env` and fill in:

| Variable | What to put | Notes |
|---|---|---|
| `GITHUB_TOKEN` | your read-only token | used by `create-save` (clone) and `scripts/fetch_pr_data.py` |
| `NEO4J_AUTH` | `neo4j/<password>` | sets the initial Neo4j password **on the first container start only** |
| `NEO4J_PASSWORD` | the same `<password>` | what the server and the helper commands use |

Rules for the password (Neo4j requirements): **at least 8 characters and
not `neo4j`**. `NEO4J_AUTH` and `NEO4J_PASSWORD` must agree — a mismatch is
the most common start-up failure (see Troubleshooting).

> **Checkpoint:** `.env` exists next to `Dockerfile`, `GITHUB_TOKEN` is
> non-empty, and the two password fields match.

---

## 2. Build the image

```bash
bash docker/run.sh build
```

One build does everything the recorded §2 environment setup did by hand:

1. **Artefact stage** — downloads the CHID replication package
   (`CHID_codes.zip`) from figshare and verifies its MD5 against the
   recorded `2c2212ac3530c5b0940fecd9bb6addfe`; unzips it; applies
   `docker/callgraph-server-linux-path.patch` (deviation **D5**, the
   separator-aware path fix — the artefact hard-codes Windows backslash
   paths and crashes on Linux otherwise).
2. **Server stage** — builds callgraph-server with Maven 3.8.6 on JDK 8
   using the same command as the recorded build
   (`mvn -B clean install -DskipTests`); the build must end in
   `BUILD SUCCESS` or the image build fails here.
3. **Runtime stage** — pins `neo4j:5.3.0` as the base, installs a pinned
   Temurin JDK 8 (for the server; Neo4j keeps its own Java 17), git and
   python3, and bakes in `apoc-5.3.0-core.jar` and
   `neo4j-graph-data-science-2.3.2.jar` — the exact plugin versions
   installed via Neo4j Desktop on 14/10/2026.


One deliberate detail you will notice in the build log: both apt-using
stages (the artefact stage and the runtime stage) pin apt to
`archive.debian.org` instead of the regular Debian mirrors. Debian 11 went
end-of-life on 31/08/2026, and the regular mirrors now serve a stale
package index whose `.deb` files are being removed, which fails
`apt-get install` with 404s even though `apt-get update` succeeds. The
archive holds the complete, frozen final state of Debian 11 (deviation
**D6**), which makes the build deterministic.

A successful build ends with the last lines of the Maven log, e.g.:

```
[INFO] BUILD SUCCESS
[INFO] Total time:  ...
```

Re-running the build is safe: Docker caches unchanged layers, so a rebuild
after a failed download or an interrupted run resumes instead of starting
over.

> **Checkpoint:** `docker images cs4928-g26` lists the image (tag
> `latest`). To override the name, set `CG_IMAGE` (see
> [Quick reference](#13-command-quick-reference)).

---

## 3. Start the stack

```bash
bash docker/run.sh up
```

This creates and starts one container (`cs4928-g26`) that runs **both**
Neo4j and callgraph-server, then waits until the server answers on :8080
(up to 300 s; first start is slower because Neo4j sets its initial
password and creates its system database).

What is wired up:

| Thing | Value |
|---|---|
| Ports | `8080` callgraph-server · `7474` Neo4j Browser · `7687` Bolt |
| Named volumes | `cs4928_g26_neo4j_data` (graph) · `cs4928_g26_neo4j_logs` (Neo4j logs) · `cs4928_g26_clone` (the artefact's clone area) |
| Bind mount | this repository at `/work` — all script outputs land in the repo's own `data/`, `results/`, `Logs/` |
| Clone path in the container | `/opt/change_impact_detector/analyzed_repositories/arduino/Arduino` |

When `up` finishes it prints the two URLs:

```
[run.sh] Neo4j Browser:   http://localhost:7474  (login: see NEO4J_USERNAME/NEO4J_PASSWORD in .env)
[run.sh] callgraph-server: http://localhost:8080
```

Now verify with:

```bash
bash docker/run.sh status
```

It prints the container state, an HTTP code for :8080 (any 1xx–5xx means
the server is listening — **404 is a healthy answer**, the artefact has no
root route), and then the three graph-size queries. On a fresh volume they
return `0`, which is exactly the "database is empty" check of recorded §2
step 1.

> **Checkpoint:** `status` shows the container running and HTTP 200/404 on
> :8080, and the graph counts are 0.

---

## 4. Build the call graph at the frozen commit

```bash
bash docker/run.sh create-save
```

This is the Docker equivalent of the recorded §2 step 2 (the PowerShell
`Invoke-RestMethod` POST): it calls
`POST /api/v1/callgraph/create-save` with
`projectIdentifier=arduino/Arduino`, `branchName=master` and your token.
The server then:

1. clones `arduino/Arduino` into the `cs4928_g26_clone` volume;
2. parses every `.java` file into a call graph (`Function` nodes,
   `CALLS` relationships) stored in Neo4j;
3. runs the artefact's PageRank over the graph.

This takes a few minutes. The JSON response (the clone path) is printed
and saved to a new file, never overwriting the recorded evidence:

```
results/raw/create_save_response_docker_<timestamp>.txt
```

Expected response text:

```
/opt/change_impact_detector/analyzed_repositories/arduino/Arduino
```

Two things that look like errors but are not:

- A line `fatal: not a git repository ... code 128` in the server log
  right after the clone comes from the artefact's Gradle clean-up step,
  which runs in the parent folder instead of the clone. Arduino has no
  Gradle/Maven files, nothing to reset, and the checkout that follows
  succeeds. This is recorded verbatim in §2 of the run procedure.
- An empty response body means failure — if that happens, check
  `bash docker/run.sh logs` and Troubleshooting below.

> **Checkpoint:** a non-empty `create_save_response_docker_*.txt` file
> containing the clone path above.

---

## 5. Verify the frozen commit and the graph size

```bash
bash docker/run.sh clone-head
bash docker/run.sh neo4j-stats
```

Expected output (matching the recorded M1 values):

```
[run.sh] a0df6e0e83b652c72bc78b0a1376c54d6ebc3bee
```

```
functions      | 2124
calls          | 3355
withPagerank   | 1701
pagerankSum    | 1.0
```

- `clone-head` reproduces §2 step 3 (frozen commit = the paper's
  `a0df6e0` checkout).
- `neo4j-stats` reproduces §2 step 4: 2,124 `Function` nodes, 3,355
  `CALLS` relationships, 1,701 functions with a `pagerank` property whose
  sum is 1.0 — confirming PageRank ran with the artefact's normalisation.

If you want these as evidence files (the original run saved
`results/raw/callgraph_stats.txt` from Neo4j Browser), tee the output:

```bash
bash docker/run.sh neo4j-stats | tee results/raw/callgraph_stats_docker_$(date +%Y%m%d_%H%M%S).txt
```

> **Checkpoint:** commit hash and all three counts match the values above.
> If they don't, stop and compare against `Notes/run_procedure.md` §2
> before continuing — later steps assume this exact graph.

---

## 6. Collect the raw PR data

```bash
bash docker/run.sh fetch
```

Runs `scripts/fetch_pr_data.py` inside the container (unchanged — it talks
to `localhost:8080`/GitHub API from within the same network namespace).
It fetches, with every request logged to `data/raw/fetch_log.csv`:

- the **10 sample PRs**;
- the **474 merged history PRs** created before the last sample PR;
- the **11 later merged bug-labelled PRs** (`data/raw/later_bug/`, used
  for RQ2 later, not in the RQ1 result).

Everything lands in `data/raw/` in this repository, as before. No method
rules are applied at this stage.

> **Checkpoint:** `data/raw/sample/`, `data/raw/history/` populated and
> `data/raw/fetch_log.csv` records the requests (a couple of 404s for
> renamed/deleted files are normal if the recorded run saw them too).

---

## 7. Prove the pipeline: pilot on #8349

Three commands, matching recorded §3:

```bash
bash docker/run.sh selftest
bash docker/run.sh query 8349
bash docker/run.sh metrics 8349
```

1. **`selftest`** runs `compute_metrics.py --selftest` against the paper's
   Figure 10 example. Expected: **PASS (44.38, C)**.
2. **`query 8349`** sends #8349's changed `.java` files (`Base.java`) to
   the server and saves request + responses to
   `results/raw/callgraph/pr_8349_*.json`. Expected: changed method
   `Base.handleClose(Editor)`, **5 impacted methods at level 1 and 7 at
   level 3**, PageRank sum 0.000666.
3. **`metrics 8349`** computes the five categories. Expected: impact A,
   buggy A, size A, churn A, merge E → **risk 10.0, category A**. Outputs:
   `results/rq1_metrics.csv` and `results/metrics_detail/pr_8349.json`.

> **Checkpoint:** selftest passes with (44.38, C) and #8349 scores 10.0/A.
> This is the point where the pipeline is proven valid on one PR, exactly
> as in the recorded pilot.

---

## 8. Run the bounded reproduction (all 10 PRs)

```bash
bash docker/run.sh fetch-pr-branches
bash docker/run.sh query --all
bash docker/run.sh metrics --all
```

- **`fetch-pr-branches`** is the execution repair from §4 step 1: it
  fetches the head branches of the PRs whose new file versions are missing
  from the clone (default `8600 8607 8621 8640 8647`; pass other numbers
  to override, e.g. `fetch-pr-branches 8600 8607`). The clone stays on
  master @ `a0df6e0` and the call graph is unchanged — the command prints
  the HEAD afterwards so you can check.
- **`query --all`** then **`metrics --all`** cover all 10 sample PRs.
  `#8349` is skipped because its pilot outputs already exist (the scripts
  never overwrite).

Expected outcome (matching recorded §4):

| PR | Risk | Category | Note |
|---|---|---|---|
| #8621 | 27.5 | B | only PR above A (see D4 on the merge-rate rule) |
| #8607 | 18.75 | A | |
| #8647 | 18.75 | A | PageRank 0.0 — its only changed existing method is a constructor with no callers |
| #8429 | 14.37 | A | |
| #8458 | 14.37 | A | |
| #8537 | 14.37 | A | |
| #8638 | 14.37 | A | |
| #8640 | 14.37 | A | PageRank 0.0003 but 0 changed methods in the impact result (changed methods have no callers) |
| #8349 | 10.0 | A | from the pilot |
| #8600 | — | NOT SCORED | contains a renamed file; the artefact's server only accepts ADDED/REMOVED/MODIFIED and rejects it (HTTP 400, evidence in `results/raw/callgraph/pr_8600_error.json`). Artefact limitation, no deviation. |

That is **9 of 10 PRs scored, categories A and B → RQ1 REPRODUCED** under
the recorded decision rule (§6).

> **Checkpoint:** `results/rq1_metrics.csv` holds the same scores as the
> table above; the full result write-up is `results/rq1_result.md`.

---

## 9. Where the evidence lands

Everything is written into the repository on the host (via the `/work`
bind mount), and nothing recorded by the original run is ever overwritten:

| Command | Files written |
|---|---|
| `create-save` | `results/raw/create_save_response_docker_<ts>.txt` |
| `fetch` | `data/raw/{sample,history,later_bug}/…`, `data/raw/fetch_log.csv` |
| `query <n>` / `query --all` | `results/raw/callgraph/pr_<n>_*.json` (errors kept as `pr_<n>_error.json`) |
| `metrics <n>` / `metrics --all` | `results/rq1_metrics.csv`, `results/metrics_detail/pr_<n>.json` |
| `save-logs` | `Logs/callgraph_server_docker_<ts>.log` |
| `clone-head` / `neo4j-stats` | printed to the console (tee them if you want files, see §5) |

The graph itself and the clone live in the named volumes, not in the repo
— that is what makes stop/start lossless.

---

## 10. Stopping, restarting, cleaning up

```bash
bash docker/run.sh stop        # stop; graph, logs and clone are kept
bash docker/run.sh start       # start again (equivalent of the recorded 15/10 restart)
bash docker/run.sh restart     # stop + start
bash docker/run.sh status      # after a restart, neo4j-stats should still show 2124
```

This mirrors the recorded restart section: the graph survives because it
lives in `cs4928_g26_neo4j_data`, the clone in `cs4928_g26_clone`.

```bash
bash docker/run.sh down        # remove the container; the three named volumes are kept
bash docker/run.sh destroy     # remove the container AND the volumes — erases the
                               # graph and the clone; asks you to type YES first
bash docker/run.sh logs -f     # follow Neo4j + server logs (docker logs passthrough)
bash docker/run.sh shell       # bash inside the container (cypher-shell available)
```

`destroy` is the "start completely fresh" button: after it, `up` recreates
the volumes and the first start re-sets the Neo4j password from `.env`.

---

## 11. Troubleshooting

**`docker` errors mentioning `npipe:////./pipe/dockerDesktopLinuxEngine`,
"error during connect" or "The system cannot find the file specified".**
The Docker engine itself is not running. The `docker` command is only a
client; on Windows it reaches the engine through a named pipe that exists
only while Docker Desktop is up. Start **Docker Desktop** from the Start
menu and wait until the whale icon in the system tray reports "Docker
Desktop is running" (a first launch may ask you to accept the service
agreement and, if WSL 2 is missing, offer to install it - accept, reboot
if prompted, then start Docker Desktop again). Verify with
`docker version`: it must print a **Server** section (e.g.
`OS/Arch: linux/amd64`), not just Client. Then re-run the command. This
applies to every command that talks to Docker (`build`, `up`, `status`,
`logs`, ...). Note also that `up` never builds the image: a fresh
checkout always needs `build` before `up` (sections 2 and 3).

**`run.sh` says ".env not found"** — you skipped §1. `cp .env.example .env`
and fill it in. `.env` is required before `up` (not before `build`).

**Neo4j fails to authenticate / the server can't connect to Bolt.**
The usual cause is `NEO4J_AUTH` and `NEO4J_PASSWORD` disagreeing, or a
password shorter than 8 characters (or literally `neo4j`). The initial
password is set from `NEO4J_AUTH` **on the first start only**; later
starts ignore it. Fix: make both variables agree and valid, then
`bash docker/run.sh destroy` and `up` again (this wipes the graph, so
re-run `create-save`).

**"port is already allocated" on `up`.** Something on your machine already
uses 8080, 7474 or 7687 — typically a local Neo4j Desktop instance or
another web app. Stop that service, or edit the `-p` lines in
`docker/run.sh` if you must move the ports (the Python scripts talk to
`localhost:8080` *inside* the container, so changing host ports is safe
for the pipeline as long as you don't need the host-side URLs).

**"I already have Neo4j installed on my laptop — do I need it?"** No. The
image bundles Neo4j 5.3.0 + APOC 5.3.0 + GDS 2.3.2 (the versions recorded
in `Notes/environment.md`), and `up` starts its own instance inside the
container; the callgraph-server reaches it at `bolt://localhost:7687`,
resolved *inside* the container, never on your laptop. Your installed
Neo4j, its databases and its password are untouched by this project. Do
stop that instance before `up` (see the port-conflict item above).

Reusing your own instance instead is possible in principle but not
supported by this setup: it would have to be exactly Neo4j 5.3.0 with the
APOC 5.3.0-core and GDS 2.3.2 plugins and unrestricted `apoc.*` / `gds.*`
procedures, with `NEO4J_URI` pointed at
`bolt://host.docker.internal:7687` in `.env` — and the `run.sh` helper
commands (e.g. `neo4j-stats`) would still query the bundled database and
report its (empty) counts. The self-contained route is what this
walkthrough and the Docker section of `Notes/run_procedure.md` describe,
and it is the only one the recorded values (2124 / 3355 / 1701) were
verified against.

**`up` reports "did not come up within 300 s".** Look at
`bash docker/run.sh logs`. A first start that is still showing Neo4j
"Starting..." messages just needs more time — `start-period` allows up to
4 minutes for the healthcheck. If you see Spring exceptions instead, work
through the auth item above.

**`create-save` failed or returned an empty body.** Check
`bash docker/run.sh logs` for the server stack trace, confirm your
`GITHUB_TOKEN` works (`curl -s -H "Authorization: Bearer $GITHUB_TOKEN"
https://api.github.com/rate_limit` should return JSON, not 401), then
re-run `create-save`. The clone volume persists, so a retry continues
from the existing clone.

**GitHub 403 / rate-limit errors during `fetch`.** The token is missing,
invalid, or exhausted. Fine-grained tokens need "Public repositories
(read-only)" metadata+contents access; wait for the rate-limit window to
reset and re-run (the scripts log every request to
`data/raw/fetch_log.csv`, so nothing is fetched twice).

**Build fails downloading the artefact, plugins or JDK.** All sources are
pinned public URLs (figshare, GitHub releases, Adoptium); a failure is
almost always transient network. Re-run `bash docker/run.sh build` —
finished layers are cached, so it resumes. The MD5 check protects you
against a silently corrupted artefact download.

The apt steps inside the build are pinned to `archive.debian.org`, so the Debian 11 end-of-life mirror purge cannot
404 them; if the archive itself is briefly unreachable or slow, just
re-run the build.

**Apple Silicon (M1/M2/M3) or ARM servers.** The pinned JDK 8 build and
the Maven image are x86_64-only. On Docker Desktop for Mac, enable
*Settings → General → Use Rosetta for x86_64/amd64 emulation* (or install
qemu user-static binfmt on ARM Linux) and the build runs under emulation,
slower but correct. A native x86_64 machine or x86 CI runner is the
smoothest path.

**Windows notes.** Use Docker Desktop with the WSL2 backend (Linux
containers mode — the default). Two equal ways to drive it: from the
preinstalled PowerShell with
`powershell -ExecutionPolicy Bypass -File docker\run.ps1 <command>` (no bash
needed; see §13), or from Git Bash / WSL with `bash docker/run.sh`, which
converts `C:\…` paths automatically for the `-v` bind mount. The original
unpatched Windows procedure (`Notes/run_procedure.md` §1–§6) remains the
fallback if you ever want a fully unmodified artefact.

**`neo4j-stats` says connection refused right after `up`.** Neo4j is
still booting. Wait a few seconds and re-run; `status` re-checks it for
you.

---

## 12. What the Docker route changes (and what it doesn't)

- **One artefact change, recorded as D5**: the 10-line Linux path patch
  (`docker/callgraph-server-linux-path.patch`) makes the server's file-path
  logic separator-aware, because the artefact hard-codes Windows backslash
  paths and throws on Linux. No analysis, parameter or metric logic is
  touched. A copy of the applied patch ships inside the image at
  `/opt/callgraph-server/APPLIED-linux-path.patch` as evidence.
- **Everything else is the artefact as published**: the source is
  MD5-verified against the recorded checksum at build time, built with the
  recorded Maven command, and run on a pinned JDK 8; Neo4j, APOC and GDS
  are pinned to the versions recorded in `Notes/environment.md`.
- **The scripts are untouched** (`scripts/*.py` are stdlib-only and
  hard-code `localhost:8080`, which is exactly what the container gives
  them). The never-overwrite evidence discipline is preserved end to end.
- **The original Windows procedure is not replaced**: §1–§6 of
  `Notes/run_procedure.md` remain the record of the run as executed; §D is
  the short Docker mapping; this file is the guided tour.

---

## 13. Command quick reference

```text
Setup        build                          build the image (artefact + patch + Maven + plugins)
             up                             create/start container, wait for :8080
             status                         health + graph-size queries
             shell                          bash inside the container

Pipeline     create-save                    §2 step 2 - clone + call graph + PageRank
             clone-head                     §2 step 3 - expect a0df6e0e83b6…3bee
             neo4j-stats                    §2 step 4 - expect 2124 / 3355 / 1701, sum 1.0
             fetch [group]                  §2        - raw PR data into data/raw/
             selftest                       §3        - Fig. 10 check (44.38, C)
             query 8349 | --all             §3/§4     - impact queries via the server
             metrics 8349 | --all           §3/§4     - risk scores -> results/rq1_metrics.csv
             fetch-pr-branches [PR…]        §4 step 1 - default: 8600 8607 8621 8640 8647

Operations   logs [args]                    docker logs passthrough
             save-logs                      container log -> Logs/callgraph_server_docker_<ts>.log
             stop | start | restart         keep everything
             down                           remove container, keep volumes
             destroy                        remove container AND volumes (erases graph + clone)
```

**Windows PowerShell:** every command above also exists in `docker\run.ps1` —
a command-for-command port of `docker/run.sh` with the same defaults and
the same `CG_*` overrides (set them as `$env:CG_IMAGE` etc. before
calling). Invoke it with
`powershell -ExecutionPolicy Bypass -File docker\run.ps1 <command>`, e.g.
`powershell -ExecutionPolicy Bypass -File docker\run.ps1 up` — it works with
the preinstalled Windows PowerShell 5.1, no Git Bash needed. Only the
invocation differs: keep using `bash docker/run.sh` on macOS/Linux and in
Git Bash. Internally `docker\run.ps1` runs `create-save` and `neo4j-stats`
from the host over the published ports (8080/7687) — the same shape as
the original recorded PowerShell procedure — and writes the same
evidence files.

Environment overrides (all optional): `CG_IMAGE` (default
`cs4928-g26:latest`), `CG_CONTAINER` (`cs4928-g26`),
`CG_VOL_DATA` / `CG_VOL_LOGS` / `CG_VOL_CLONE` (the three named volumes).
For example, a second isolated run:

```bash
CG_CONTAINER=cs4928-g26-b CG_VOL_DATA=cs4928_g26_neo4j_data_b \
CG_VOL_LOGS=cs4928_g26_neo4j_logs_b CG_VOL_CLONE=cs4928_g26_clone_b \
bash docker/run.sh up
```

(If you also want it parallel to the first, the published ports in
`docker/run.sh` need a matching change.)
