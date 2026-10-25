# syntax=docker/dockerfile:1
###############################################################################
# CS4928-G26 - Docker image for the CHID reproduction pipeline
#
# One container = Neo4j 5.3.0 (community) + APOC 5.3.0 + GDS 2.3.2
#                 + callgraph-server (Spring Boot 2.6.4 on JDK 8)
#                 + git + python3 for the pipeline scripts in scripts/
#
# The callgraph-server source is the unmodified artefact from figshare
# (CHID_codes.zip, MD5-checked at build time), except the minimal Linux path
# patch applied below (docker/callgraph-server-linux-path.patch; recorded as
# deviation D5 in Notes/deviations.md). The recorded Windows procedure in
# Notes/run_procedure.md remains the authoritative unpatched record.
#
# Build:  bash docker/run.sh build
# Run:    bash docker/run.sh up
###############################################################################

# ---- Stage 1: fetch the artefact and apply the Linux path patch -------------
# (separate stage so the artefact download/patch is cached independently of
#  the Maven build. Base is bullseye-slim and apt is pinned to
#  archive.debian.org up front: Debian 11 went EOL on 31/08/2026, and the
#  regular mirrors still serve a bullseye-security index whose .deb files
#  are being purged, which makes `apt-get install` fail with 404s even
#  though `apt-get update` succeeds. The archive holds the complete frozen
#  final state (verified 25/10/2026) and serves plain HTTP, so no TLS trust
#  is needed before ca-certificates is installed. Deviation D6.)
FROM debian:bullseye-slim AS artefact-prep

ARG CHID_ARTEFACT_URL=https://ndownloader.figshare.com/files/50340738
ARG CHID_ARTEFACT_MD5=2c2212ac3530c5b0940fecd9bb6addfe

RUN set -eux; \
    sed -i 's|deb.debian.org/debian|archive.debian.org/debian|g; s|deb.debian.org/debian-security|archive.debian.org/debian-security|g; s|security.debian.org|archive.debian.org/debian-security|g' /etc/apt/sources.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates unzip patch; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Download the CHID replication package and verify its checksum (the file the
# team downloaded on 09/10/2026; MD5 confirmed in Notes/environment.md).
RUN curl -fsSL -o CHID_codes.zip "$CHID_ARTEFACT_URL" \
 && echo "$CHID_ARTEFACT_MD5  CHID_codes.zip" | md5sum -c - \
 && unzip -q CHID_codes.zip -x "__MACOSX/*" \
 && rm -f CHID_codes.zip

# Apply the Linux path patch (separator-aware paths only; see D5), keeping a
# copy of the patch inside the image as evidence of what was applied. The
# patch headers are a/callgraph-server/... (diffed from the artefact root),
# so -p1 must be applied from /build - running it from inside callgraph-server
# would look for callgraph-server/callgraph-server/... and fail. -t -N keep
# the step non-interactive and forward-only.
COPY docker/callgraph-server-linux-path.patch /build/
RUN patch -t -N -p1 -d /build < /build/callgraph-server-linux-path.patch \
 && cp /build/callgraph-server-linux-path.patch /build/callgraph-server/APPLIED-linux-path.patch

# ---- Stage 2: build callgraph-server (JDK 8 + Maven 3.8.6, as recorded) -----
FROM maven:3.8.6-openjdk-8 AS server-build

COPY --from=artefact-prep /build/callgraph-server /build/callgraph-server

# Same build command as the recorded procedure (Logs/callgraph_build_14-10-2026.log)
RUN cd /build/callgraph-server \
 && (mvn -B clean install -DskipTests > /build/callgraph_build_docker.log 2>&1 \
     || (tail -n 100 /build/callgraph_build_docker.log && exit 1)) \
 && grep -q "BUILD SUCCESS" /build/callgraph_build_docker.log \
 && tail -n 3 /build/callgraph_build_docker.log

# Assemble what the runtime image keeps: executable jar, patched source,
# pom, build log and the applied patch (evidence chain inside the image).
RUN mkdir -p /staging/callgraph-server \
 && cp /build/callgraph-server/target/callgraph-0.0.1-SNAPSHOT.jar /staging/callgraph-server/ \
 && cp -r /build/callgraph-server/src /staging/callgraph-server/src \
 && cp /build/callgraph-server/pom.xml /staging/callgraph-server/ \
 && cp /build/callgraph-server/APPLIED-linux-path.patch /staging/callgraph-server/ \
 && cp /build/callgraph_build_docker.log /staging/callgraph-server/

# ---- Stage 3: runtime on the official Neo4j 5.3.0 image ---------------------
FROM neo4j:5.3.0

USER root

# git + python3 + curl: the pipeline scripts need git/python3 (stdlib-only
# otherwise) and curl is required for the JDK/plugin downloads below - it is
# installed here instead of being assumed present in the base image. Same
# archive.debian.org pin as the artefact stage: the neo4j:5.3.0 base is
# Debian 11 (EOL 31/08/2026), whose regular apt mirrors no longer serve all
# .deb files (deviation D6). The rewrite covers /etc/apt/sources.list AND any
# /etc/apt/sources.list.d/*.list, whichever layout the base image uses.
RUN set -eux; \
    find /etc/apt -maxdepth 2 -name '*.list' -exec sed -i 's|deb.debian.org/debian|archive.debian.org/debian|g; s|deb.debian.org/debian-security|archive.debian.org/debian-security|g; s|security.debian.org|archive.debian.org/debian-security|g' {} +; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates git python3 procps; \
    rm -rf /var/lib/apt/lists/*

# Pinned Temurin JDK 8 for callgraph-server. Neo4j keeps its own Java 17 at
# /opt/java/openjdk (untouched); the entrypoint selects Java 8 for the server.
ARG JAVA8_URL=https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u412-b08/OpenJDK8U-jdk_x64_linux_hotspot_8u412b08.tar.gz
RUN mkdir -p /opt/java8 \
 && curl -fsSL "$JAVA8_URL" | tar -xz --strip-components=1 -C /opt/java8

# callgraph-server (patched artefact) from stage 2
COPY --from=server-build /staging/callgraph-server /opt/callgraph-server

# Neo4j plugins, pinned to the versions recorded in Notes/environment.md
# (Neo4j Desktop installed exactly these on 14/10/2026).
ARG APOC_JAR_URL=https://github.com/neo4j/apoc/releases/download/5.3.0/apoc-5.3.0-core.jar
ARG GDS_JAR_URL=https://github.com/neo4j/graph-data-science/releases/download/2.3.2/neo4j-graph-data-science-2.3.2.jar
RUN curl -fsSL -o "$NEO4J_HOME/plugins/apoc-5.3.0-core.jar" "$APOC_JAR_URL" \
 && curl -fsSL -o "$NEO4J_HOME/plugins/neo4j-graph-data-science-2.3.2.jar" "$GDS_JAR_URL"

# The artefact calls gds.graph.*, apoc.do.when and gds.pageRank.write from
# driver sessions, so both procedure families must be allowed/unrestricted.
ENV NEO4J_dbms_security_procedures_unrestricted=apoc.*,gds.* \
    NEO4J_dbms_security_procedures_allowlist=apoc.*,gds.*

# callgraph-server configuration. Spring Boot's relaxed binding maps these
# environment variables onto the artefact's neo4j.uri / neo4j.username /
# neo4j.password properties, so application.properties stays untouched.
# NEO4J_PASSWORD is supplied at runtime (see .env.example).
ENV CG_HOME=/opt/callgraph-server \
    JAVA8_HOME=/opt/java8 \
    NEO4J_URI=bolt://localhost:7687 \
    NEO4J_USERNAME=neo4j

COPY docker/cg-entrypoint.sh /usr/local/bin/cg-entrypoint.sh
RUN chmod +x /usr/local/bin/cg-entrypoint.sh

# Container layout:
#   /work                        bind-mount of the CS4928-G26 project
#   /opt/change_impact_detector  artefact clone area (named volume)
#   /data, /logs                 Neo4j data/logs (named volumes)
# `docker build` prints two SecretsUsedInArgOrEnv lint warnings for the ENV
# block below - expected and safe: both values are deliberately empty in the
# image and are injected at `up` time from .env (--env-file), never baked
# into any layer.
ENV NEO4J_PASSWORD= \
    GITHUB_TOKEN=
WORKDIR /work

EXPOSE 8080 7474 7687

# Any HTTP answer from the server means Tomcat is listening (the artefact has
# no root route, so 404 is a healthy answer; 000 = nothing listening).
HEALTHCHECK --interval=30s --timeout=10s --start-period=240s --retries=5 \
  CMD ["/bin/bash", "-c", "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/ | grep -qE '^[1-5][0-9]{2}$'"]

# Keep the base image's tini init (zombie reaping, group signal handling).
ENTRYPOINT ["tini", "-g", "--", "/usr/local/bin/cg-entrypoint.sh"]
