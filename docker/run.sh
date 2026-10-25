#!/usr/bin/env bash
###############################################################################
# docker/run.sh - helper for the Dockerised CS4928-G26 pipeline.
#
# Usage: bash docker/run.sh <command> [args...]
# See `bash docker/run.sh help`. The mapping to the recorded procedure steps
# is documented in Notes/run_procedure.md (Docker section).
#
# Requires: docker, curl, bash. On Windows use WSL or Git Bash.
###############################################################################
set -euo pipefail

IMAGE="${CG_IMAGE:-cs4928-g26:latest}"
NAME="${CG_CONTAINER:-cs4928-g26}"
VOL_DATA="${CG_VOL_DATA:-cs4928_g26_neo4j_data}"
VOL_LOGS="${CG_VOL_LOGS:-cs4928_g26_neo4j_logs}"
VOL_CLONE="${CG_VOL_CLONE:-cs4928_g26_clone}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLONE_IN_CONTAINER="/opt/change_impact_detector/analyzed_repositories/arduino/Arduino"
# The five PR branches fetched in the recorded §4 step (override by passing PR numbers)
DEFAULT_PR_BRANCHES=(8600 8607 8621 8640 8647)

log() { printf '[run.sh] %s\n' "$*"; }
die() { printf '[run.sh] ERROR: %s\n' "$*" >&2; exit 1; }

# Git Bash on Windows: "C:/..." would be mangled by MSYS path conversion in -v flags
host_path() {
    if [ -n "${MSYSTEM:-}" ] && command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1"
    else
        printf '%s' "$1"
    fi
}

require_env() {
    [ -f "$ROOT/.env" ] || die "$ROOT/.env not found. Copy .env.example to .env and fill in GITHUB_TOKEN and the Neo4j password."
}

container_exists() {
    # docker inspect falls back to IMAGE lookup when no container
    # carries the name, so plain 'inspect' succeeds against the
    # cs4928-g26 image even though the container does not exist.
    # docker ps -a lists containers only - exact-name match is
    # unambiguous.
    docker ps -a --format '{{.Names}}' | grep -qx "$NAME"
}

require_container() {
    container_exists || die "container '$NAME' does not exist. Run: bash docker/run.sh up"
}

cexec() { docker exec "$NAME" "$@"; }

server_code() { curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080/" 2>/dev/null || printf '000'; }

wait_for_server() {
    printf '[run.sh] waiting for callgraph-server on :8080 '
    for _ in $(seq 1 150); do
        code="$(server_code)"
        if [[ "$code" =~ ^[1-5][0-9]{2}$ ]]; then
            echo " up (HTTP $code)"
            return 0
        fi
        printf '.'; sleep 2
    done
    echo
    die "the server did not come up within 300s. Check: docker logs $NAME"
}

cmd_build() {
    docker build -t "$IMAGE" "$ROOT"
}

cmd_up() {
    require_env
    if container_exists; then
        if [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = "true" ]; then
            log "container '$NAME' is already running"; return 0
        fi
        log "starting existing container '$NAME'"
        docker start "$NAME" >/dev/null
    else
        log "creating container '$NAME' (image $IMAGE)"
        docker run -d --name "$NAME" \
            -p 8080:8080 -p 7474:7474 -p 7687:7687 \
            --env-file "$ROOT/.env" \
            -v "${VOL_DATA}":/data \
            -v "${VOL_LOGS}":/logs \
            -v "${VOL_CLONE}":/opt/change_impact_detector \
            -v "$(host_path "$ROOT")":/work \
            "$IMAGE" >/dev/null
    fi
    wait_for_server
    log "Neo4j Browser:   http://localhost:7474  (login: see NEO4J_USERNAME/NEO4J_PASSWORD in .env)"
    log "callgraph-server: http://localhost:8080"
}

cmd_status() {
    require_container
    state="$(docker inspect -f '{{.State.Status}} (health: {{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}})' "$NAME")"
    log "container: $NAME - $state"
    code="$(server_code)"
    log "callgraph-server :8080 -> HTTP $code (any 1xx-5xx code means it is listening)"
    if [[ "$code" =~ ^[1-5][0-9]{2}$ ]]; then
        cmd_neo4j_stats || log "Neo4j stats failed - is the database up yet? (docker logs $NAME)"
    fi
}

cmd_neo4j_stats() {
    require_container
    # Same three queries as the recorded §2 step 4 (results/raw/callgraph_stats.txt).
    # ONE positional argument: cypher-shell 5.3.0 accepts exactly one cypher
    # positional (usage line shows [cypher]) and rejects further positionals
    # with 'unrecognized arguments' - verified against the real 5.3.0 binary.
    cexec bash -c 'cypher-shell -a bolt://localhost:7687 -u "$NEO4J_USERNAME" -p "$NEO4J_PASSWORD" \
        "MATCH (f:Function) RETURN count(f) AS functions; MATCH ()-[r:CALLS]->() RETURN count(r) AS calls; MATCH (f:Function) WHERE f.pagerank IS NOT NULL RETURN count(f) AS withPagerank, sum(f.pagerank) AS pagerankSum;"'
}

cmd_create_save() {
    require_container
    # Docker equivalent of the recorded §2 step 2 (PowerShell Invoke-RestMethod):
    # body identical to $body = @{ projectIdentifier=...; branchName=...; githubToken=$env:GITHUB_TOKEN }
    ts="$(date +%Y%m%d_%H%M%S)"
    out="$ROOT/results/raw/create_save_response_docker_${ts}.txt"
    log "posting create-save (clone + call graph + PageRank; takes a few minutes) ..."
    cexec bash -c 'curl -sS -X POST http://localhost:8080/api/v1/callgraph/create-save \
        -H "Content-Type: application/json" \
        -d "{\"projectIdentifier\":\"arduino/Arduino\",\"branchName\":\"master\",\"githubToken\":\"$GITHUB_TOKEN\"}"' \
        > "$out" || { cat "$out" >&2; die "create-save failed (see output above and docker logs $NAME)"; }
    log "response saved to results/raw/create_save_response_docker_${ts}.txt (empty response would mean failure)"
    cat "$out"; echo
    log "expected: /opt/change_impact_detector/analyzed_repositories/arduino/Arduino"
}

cmd_clone_head() {
    require_container
    # Docker equivalent of the recorded §2 step 3 (expected a0df6e0e83b652c72bc78b0a1376c54d6ebc3bee)
    cexec git -C "$CLONE_IN_CONTAINER" rev-parse HEAD
}

cmd_fetch_pr_branches() {
    require_container
    # Docker equivalent of the recorded §4 step 1: fetch the PR head branches
    # whose new file versions are missing from the clone (execution repair only).
    refs=("$@")
    [ "${#refs[@]}" -eq 0 ] && refs=("${DEFAULT_PR_BRANCHES[@]}")
    args=()
    for p in "${refs[@]}"; do
        args+=("+refs/pull/${p}/head:refs/remotes/origin/pr/${p}")
    done
    cexec git -C "$CLONE_IN_CONTAINER" fetch origin "${args[@]}"
    log "fetched ${#refs[@]} PR branch(es); clone HEAD unchanged:"
    cmd_clone_head
}

cmd_fetch()   { require_container; cexec python3 scripts/fetch_pr_data.py "$@"; }
cmd_query()   { require_container; cexec python3 scripts/query_callgraph.py "$@"; }
cmd_metrics() { require_container; cexec python3 scripts/compute_metrics.py "$@"; }
cmd_selftest() { require_container; cexec python3 scripts/compute_metrics.py --selftest; }

cmd_logs()      { require_container; docker logs "$@" "$NAME"; }
cmd_save_logs() {
    require_container
    ts="$(date +%Y%m%d_%H%M%S)"
    out="$ROOT/Logs/callgraph_server_docker_${ts}.log"
    docker logs --timestamps "$NAME" > "$out" 2>&1
    log "container log saved to ${out#$ROOT/}"
}
cmd_shell()     { require_container; docker exec -it "$NAME" bash; }
cmd_stop()      { require_container; docker stop "$NAME" >/dev/null; log "stopped '$NAME' (graph and clone kept)"; }
cmd_start()     { require_container; docker start "$NAME" >/dev/null; wait_for_server; }
cmd_restart()   { cmd_stop; cmd_start; }
cmd_down()      { require_container; docker rm -f "$NAME" >/dev/null; log "removed '$NAME' (named volumes kept: $VOL_DATA $VOL_LOGS $VOL_CLONE)"; }
cmd_destroy()   {
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    printf '[run.sh] deleting volumes %s %s %s - this erases the graph, its logs and the clone. Type YES to confirm: ' \
        "$VOL_DATA" "$VOL_LOGS" "$VOL_CLONE"
    read -r ans
    [ "$ans" = "YES" ] || { log "aborted"; return 0; }
    docker volume rm "$VOL_DATA" "$VOL_LOGS" "$VOL_CLONE" >/dev/null 2>&1 || true
    log "volumes deleted"
}

cmd_help() {
    cat <<'EOF'
Usage: bash docker/run.sh <command> [args...]

Setup
  build              Build the image (downloads the figshare artefact, applies the
                     Linux path patch, builds callgraph-server, pins Neo4j plugins)
  up                 Create/start the container and wait until :8080 answers
                     (ports 8080 7474 7687; bind-mounts the project at /work;
                     named volumes keep the Neo4j graph, its logs and the clone)
  status             Container health + the §2 graph-size queries
  shell              Open a bash shell inside the container

Recorded procedure equivalents (Notes/run_procedure.md)
  create-save        §2 step 2 - POST /api/v1/callgraph/create-save
                     (clone arduino/Arduino @ master, build call graph, PageRank)
  clone-head         §2 step 3 - git rev-parse HEAD of the clone (expect
                     a0df6e0e83b652c72bc78b0a1376c54d6ebc3bee)
  neo4j-stats        §2 step 4 - Function/CALLS/PageRank counts via cypher-shell
  fetch [group]      §2        - python scripts/fetch_pr_data.py [group]
  selftest           §3        - compute_metrics.py --selftest (Fig. 10: 44.38, C)
  query <n|--all>    §3/§4     - python scripts/query_callgraph.py ...
  metrics <n|--all>  §3/§4     - python scripts/compute_metrics.py ...
  fetch-pr-branches [PR...]
                     §4 step 1 - git fetch of the PR head branches
                     (default: 8600 8607 8621 8640 8647)

Operations
  logs [docker-logs-args]   Follow/print container logs (Neo4j + server)
  save-logs                 Write container logs to Logs/callgraph_server_docker_<ts>.log
  stop | start | restart    Stop/start without deleting anything
  down                      Remove the container (named volumes are kept)
  destroy                   Remove the container AND the named volumes (erases the graph)

Environment
  CG_IMAGE, CG_CONTAINER, CG_VOL_DATA, CG_VOL_LOGS, CG_VOL_CLONE override defaults.
  .env (from .env.example) must exist before `up`.
EOF
}

cmd="${1:-help}"
shift || true
case "$cmd" in
    build)             cmd_build ;;
    up)                cmd_up ;;
    status)            cmd_status ;;
    neo4j-stats)       cmd_neo4j_stats ;;
    create-save)       cmd_create_save ;;
    clone-head)        cmd_clone_head ;;
    fetch-pr-branches) cmd_fetch_pr_branches "$@" ;;
    fetch)             cmd_fetch "$@" ;;
    query)             cmd_query "$@" ;;
    metrics)           cmd_metrics "$@" ;;
    selftest)          cmd_selftest ;;
    logs)              cmd_logs "$@" ;;
    save-logs)         cmd_save_logs ;;
    shell)             cmd_shell ;;
    stop)              cmd_stop ;;
    start)             cmd_start ;;
    restart)           cmd_restart ;;
    down)              cmd_down ;;
    destroy)           cmd_destroy ;;
    help|-h|--help)    cmd_help ;;
    *)                 die "unknown command '$cmd'. See: bash docker/run.sh help" ;;
esac
