# Environment (recorded 14/10/2026)

| Item                | Value                                                                                                          |
|---------------------|----------------------------------------------------------------------------------------------------------------|
| OS                  | Windows Version 25H2                                                                                           |
| Java                | JDK 1.8.0_202                                                                                                  |
| Maven               | 3.8.6 (via mvnw, maven-wrapper 3.1.0)                                                                          |
| callgraph-server    | Spring Boot 2.6.4, JavaParser 3.24.8, JGraphT 1.3.0, Neo4j Java driver starter 4.3.6.0 (from pom.xml)          |
| Neo4j               | 5.3.0 (Neo4j Desktop Version 2.2.1)                                                                            |
| Neo4j plugins       | APOC 5.3.0, Graph Data Science 2.3.2                                                                           |
| Neo4j runtime       | Java 17.0.19 (Azul Zulu, bundled with Neo4j Desktop); confirmed by "VM Version: 17.0.19+10-LTS" in the instance's debug.log. Separate from callgraph-server, which runs on JDK 1.8.0_202. |
| Git                 | 2.52.0.windows.1                                                                                               |
| Python              | 3.13.16                                                                                                        |
| Artefact            | CHID replication package, https://doi.org/10.6084/m9.figshare.27643755.v1 (downloaded 09/10/2026)              |
| Analysed repository | arduino/Arduino master @ a0df6e0e83b652c72bc78b0a1376c54d6ebc3bee (master head confirmed unchanged 14/10/2026) |

Java 1.8.0_202 and Spring Boot 2.6.4 are confirmed at runtime by Logs/callgraph_server_14102026.log ("Starting CallgraphServerApplication using Java 1.8.0_202", ":: Spring Boot :: (v2.6.4)"). Other callgraph-server library versions are taken from its pom.xml. The Maven version is from .mvn/wrapper/maven-wrapper.properties.


Docker environment (image added 24/10/2026, not used for the original run)

| Item                    | Value                                                                                                                                          |
|-------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| Image                   | cs4928-g26:latest, built from the repo Dockerfile (base: official neo4j:5.3.0 image)                                                           |
| Base OS                 | Debian 11 (bullseye), from the neo4j:5.3.0 image                                                                                               |
| Neo4j                   | 5.3.0 community (official image, tarball checksummed by the image build). The original run used Neo4j Desktop's Enterprise edition; no effect on PageRank or the queries used, confirmed by identical graph stats (2,124 / 3,355 / 1,701, sum 1.0). |                                                                       |
| Neo4j plugins           | APOC 5.3.0 (apoc-5.3.0-core.jar), Graph Data Science 2.3.2 - same jars as the recorded environment, baked into the image                       |
| Java (callgraph-server) | Temurin JDK 8u412-b08 (Java 1.8), at /opt/java8                                                                                                |
| Java (Neo4j)            | Java 17 bundled at /opt/java/openjdk by the official image                                                                                     |
| Build toolchain         | Maven 3.8.6 (maven:3.8.6-openjdk-8 build stage), `mvn -B clean install -DskipTests`                                                            |
| callgraph-server        | Artefact source (CHID_codes.zip, MD5 2c2212ac3530c5b0940fecd9bb6addfe) + docker/callgraph-server-linux-path.patch (deviation D5)               |
| Git                     | Debian bullseye git package (inside the image)                                                                                                 |
| Python                  | Debian bullseye python3 (3.9.x; scripts are stdlib-only, no behavioural difference from the recorded 3.13)                                     |
| Artefact URL            | https://ndownloader.figshare.com/files/50340738 (downloaded and MD5-checked at build time)                                                     |
| Ports                   | 8080 (callgraph-server), 7474/7687 (Neo4j Browser/Bolt)                                                                                        |
| Volumes                 | cs4928_g26_neo4j_data -> /data, cs4928_g26_neo4j_logs -> /logs, cs4928_g26_clone -> /opt/change_impact_detector; project bind-mounted at /work |

JDK 1.8.0_202 (recorded above) is replaced inside the image by Temurin
8u412-b08: same Java 1.8 language/runtime level, different vendor build;
Spring Boot 2.6.4 and the pom dependencies are unchanged. The Docker
environment exists so the pipeline can be re-run outside the recorded
Windows setup; it is not part of the original run's evidence.