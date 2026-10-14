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