# Environment (recorded 14/10/2026)

| Item | Value                                                                                                 |
|---|-------------------------------------------------------------------------------------------------------|
| OS | Windows Version 25H2                                                                                  |
| Java | JDK 1.8.0_202                                                                                         |
| Maven | 3.8.6 (via mvnw, maven-wrapper 3.1.0)                                                                 |
| callgraph-server | Spring Boot 2.6.4, JavaParser 3.24.8, JGraphT 1.3.0, Neo4j Java driver starter 4.3.6.0 (from pom.xml) |
| Neo4j | 5.3.0 (Neo4j Desktop Version 2.2.1)                                                                                |
| Neo4j plugins | APOC 5.3.0, Graph Data Science 2.3.2                                                                  |
| Git | 2.52.0.windows.1                                                                                      |
| Python | 3.13.16                                                                                               |
| Artefact | CHID replication package, https://doi.org/10.6084/m9.figshare.27643755.v1 (downloaded 09/10/2026)     |
| Analysed repository | arduino/Arduino master @ a0df6e0e83b652c72bc78b0a1376c54d6ebc3bee (master head confirmed unchanged 14/10/2026) |

Java 1.8.0_202 and Spring Boot 2.6.4 are confirmed at runtime by Logs/callgraph_server_14102026.log ("Starting CallgraphServerApplication using Java 1.8.0_202", ":: Spring Boot :: (v2.6.4)"). Other callgraph-server library versions are taken from its pom.xml. The Maven version is from .mvn/wrapper/maven-wrapper.properties.

# Run procedure

## Step 2 (14/10/2026)
1. Neo4j Desktop 2.2.1: created a local instance on Neo4j 5.3.0 with the APOC 5.3.0 and Graph Data Science 2.3.2 plugins (APOC was installed on the correct version automatically through Neo4J desktop and GDS can be found here: https://github.com/neo4j/graph-data-science/releases/tag/2.3.2. Started the instance.
2. callgraph-server used from Desktop\27643755\CHID_codes\callgraph-server, unmodified except src\main\resources\application.properties to configure the neo4J URI and password.
3. Build callgraph-server (JDK 1.8.0_202), run from PowerShell:
   cmd /c "cd /d ""...\27643755\CHID_codes\callgraph-server"" && mvnw.cmd -B clean install -DskipTests > ""...\CS4928-G26\Logs\callgraph_build_14-10-2026.log"" 2>&1"
    - Compiles the server with Maven, skipping its tests.
    - All output is written to Logs/callgraph_build_14-10-2026.log, which ends in BUILD SUCCESS.
4. Start callgraph-server, run from a separate PowerShell window that stays open:
   cmd /c "cd /d ""...\27643755\CHID_codes\callgraph-server"" && mvnw.cmd spring-boot:run > ""...\CS4928-G26\Logs\callgraph_server_14102026.log"" 2>&1"
    - Starts the server on http://localhost:8080. It keeps running until the window is closed.
    - All output is written to Logs/callgraph_server_14102026.log, which shows "Started CallgraphServerApplication".
5. GitHub access: read-only fine-grained token for public repositories, stored in the GITHUB_TOKEN system environment variable (not recorded).