#!/bin/bash
###############################################################################
# CS4928-G26 container entrypoint.
#
# Starts Neo4j 5.3.0 (through the official image entrypoint, which also
# handles NEO4J_AUTH / first-start password) and then callgraph-server
# (Spring Boot on the pinned JDK 8) in the same container, keeping both
# supervised until one of them exits.
###############################################################################
set -euo pipefail

NEO4J_HOME="${NEO4J_HOME:-/var/lib/neo4j}"
CG_HOME="${CG_HOME:-/opt/callgraph-server}"

# --- required configuration ---------------------------------------------------
: "${NEO4J_AUTH:?NEO4J_AUTH is required, e.g. NEO4J_AUTH=neo4j/change-me-please (see .env.example)}"
: "${NEO4J_PASSWORD:?NEO4J_PASSWORD is required and must match the password part of NEO4J_AUTH (see .env.example)}"
export NEO4J_URI="${NEO4J_URI:-bolt://localhost:7687}"
export NEO4J_USERNAME="${NEO4J_USERNAME:-neo4j}"

if [ "${NEO4J_AUTH}" != "none" ]; then
    auth_pw="${NEO4J_AUTH#*/}"
    if [ "${auth_pw}" = "neo4j" ]; then
        echo "ERROR: the NEO4J_AUTH password must not be 'neo4j' (Neo4j requirement)." >&2
        exit 1
    fi
    if [ "${#auth_pw}" -lt 8 ]; then
        echo "ERROR: the NEO4J_AUTH password must be at least 8 characters (Neo4j requirement)." >&2
        exit 1
    fi
fi

# --- start Neo4j in the background via the official entrypoint ----------------
# NEO4J_URI / NEO4J_USERNAME / NEO4J_PASSWORD are hidden from the Neo4j
# process on purpose: the official entrypoint turns every NEO4J_* variable
# into a neo4j.conf setting, and 'uri'/'username'/'password' are not valid
# Neo4j settings (Neo4j 5 fails to start on unknown settings). They remain
# in this shell's environment for the server and the docker exec commands.

# A stop/start keeps the container filesystem, so the previous boot's
# pidfile survives. The neo4j launcher then reads that stale pid, finds a
# live process wearing it (pids are reused within seconds of boot), refuses
# to start with "Neo4j is already running (pid:N)" and exits, which aborts
# this entrypoint - observed verbatim on the first `docker start` of this
# container. Remove the stale pidfile before every boot.
rm -f "${NEO4J_HOME}/run/neo4j.pid"
env -u NEO4J_URI -u NEO4J_USERNAME -u NEO4J_PASSWORD \
    /startup/docker-entrypoint.sh neo4j &
NEO4J_PID=$!

cleanup() {
    echo "[cg] stopping Neo4j and callgraph-server ..."
    kill "${NEO4J_PID}" 2>/dev/null || true
    if [ -n "${SERVER_PID:-}" ]; then
        kill "${SERVER_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 0' INT TERM

# --- wait until bolt answers ----------------------------------------------------
echo "[cg] waiting for Neo4j bolt on bolt://localhost:7687 ..."
ready=""
for _ in $(seq 1 150); do
    if ! kill -0 "${NEO4J_PID}" 2>/dev/null; then
        echo "ERROR: the Neo4j process exited during startup (see: docker logs <container>)." >&2
        exit 1
    fi
    if "$NEO4J_HOME/bin/cypher-shell" -a "bolt://localhost:7687" \
           -u "$NEO4J_USERNAME" -p "$NEO4J_PASSWORD" \
           "RETURN 1 AS ready;" >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 2
done
if [ -z "$ready" ]; then
    echo "ERROR: Neo4j did not become ready within 300s (see: docker logs <container>)." >&2
    exit 1
fi
echo "[cg] Neo4j is up."

# --- start callgraph-server on the pinned JDK 8 --------------------------------
# The working directory matters: the artefact derives the clone location as
#   <parent of user.dir>/change_impact_detector/analyzed_repositories/<owner>/<repo>
# so the server must run from /opt/callgraph-server, making the clone
# /opt/change_impact_detector/analyzed_repositories/arduino/Arduino.
cd "$CG_HOME"
export JAVA_HOME="${JAVA8_HOME:-/opt/java8}"
export PATH="${JAVA_HOME}/bin:${PATH}"
java -jar callgraph-0.0.1-SNAPSHOT.jar &
SERVER_PID=$!
echo "[cg] callgraph-server starting on http://localhost:8080 (pid ${SERVER_PID}, $(java -version 2>&1 | head -n 1))"

# --- keep both processes supervised ---------------------------------------------
while kill -0 "${NEO4J_PID}" 2>/dev/null && kill -0 "${SERVER_PID}" 2>/dev/null; do
    sleep 5
done
echo "ERROR: a container process exited unexpectedly (see: docker logs <container>)." >&2
exit 1
