# docker/run.ps1 - PowerShell twin of docker/run.sh for the Dockerised
# CS4928-G26 pipeline. Command-for-command port: same subcommands, same
# defaults, same .env handling. Runs on the preinstalled Windows PowerShell
# 5.1 (or PowerShell 7); no Git Bash / WSL needed.
#
# Usage (from cmd or any PowerShell session):
#   powershell -ExecutionPolicy Bypass -File docker\run.ps1 <command> [args...]
#   powershell -ExecutionPolicy Bypass -File docker\run.ps1 help
#
# Differences from run.sh (host-side only, output files identical):
#   - create-save and neo4j-stats run from the host over the published ports
#     (8080 / 7687) instead of inside the container. This mirrors the original
#     recorded PowerShell procedure (Invoke-RestMethod in
#     Notes/run_procedure.md Section 2) and sidesteps PowerShell 5.1's
#     native argument-quoting pitfalls with embedded double quotes.
#   - the bind mount uses the Windows path directly (Docker Desktop accepts
#     it), so no cygpath/MSYS conversion is needed.
# Requires: Docker Desktop, curl.exe (bundled with Windows 10 1803+).

$ErrorActionPreference = 'Continue'

$Image     = if ($env:CG_IMAGE)     { $env:CG_IMAGE }     else { 'cs4928-g26:latest' }
$Name      = if ($env:CG_CONTAINER) { $env:CG_CONTAINER } else { 'cs4928-g26' }
$VolData   = if ($env:CG_VOL_DATA)  { $env:CG_VOL_DATA }  else { 'cs4928_g26_neo4j_data' }
$VolLogs   = if ($env:CG_VOL_LOGS)  { $env:CG_VOL_LOGS }  else { 'cs4928_g26_neo4j_logs' }
$VolClone  = if ($env:CG_VOL_CLONE) { $env:CG_VOL_CLONE } else { 'cs4928_g26_clone' }
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot }
             elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path }
             else { (Get-Location).Path }
$Root      = Split-Path -Parent $ScriptDir
$RootFwd   = $Root -replace '\\', '/'
$CloneInContainer = '/opt/change_impact_detector/analyzed_repositories/arduino/Arduino'
# The five PR branches fetched in the recorded Section 4 step (override by
# passing PR numbers, e.g.: ... run.ps1 fetch-pr-branches 8600 8607)
$DefaultPrBranches = @('8600', '8607', '8621', '8640', '8647')
# PowerShell 5.1 has no $IsWindows (always Windows); PowerShell 7 does.
$NullDev = if ($IsWindows -eq $false) { '/dev/null' } else { 'NUL' }

function Log { param([string]$m) Write-Host "[run.ps1] $m" }
function Die { param([string]$m) [Console]::Error.WriteLine("[run.ps1] ERROR: $m"); exit 1 }

function Require-Env {
    if (-not (Test-Path (Join-Path $Root '.env'))) {
        Die "$Root\.env not found. Copy .env.example to .env and fill in GITHUB_TOKEN and the Neo4j password."
    }
}

function Test-ContainerExists {
    # docker inspect falls back to IMAGE lookup when no container
    # carries the name, so a plain inspect 'succeeds' against the
    # cs4928-g26 image right after a build and every guarded command
    # then fails on a container that never existed. docker ps -a
    # lists containers only, so an exact-name match is unambiguous.
    return (@(& docker ps -a --format '{{.Names}}') -contains $Name)
}

function Require-Container {
    if (-not (Test-ContainerExists)) {
        Die "container '$Name' does not exist. Run: powershell -ExecutionPolicy Bypass -File docker\run.ps1 up"
    }
}

function Get-DotEnv {
    # Minimal .env parser: KEY=VALUE lines, '#' comments, optional quotes.
    $map = @{}
    foreach ($line in Get-Content (Join-Path $Root '.env')) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        $v = $t.Substring($i + 1).Trim()
        if ($v.Length -ge 2) {
            if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
                $v = $v.Substring(1, $v.Length - 2)
            }
        }
        $map[$t.Substring(0, $i).Trim()] = $v
    }
    return $map
}

function Get-ServerCode {
    # Same semantics as run.sh: any 1xx-5xx means Tomcat is listening
    # (404 is a healthy answer, the artefact has no root route); 000 = down.
    $code = & curl.exe -s -o $NullDev -w '%{http_code}' http://localhost:8080/ 2>$null
    if (-not $code) { $code = '000' }
    return "$code"
}

function Wait-ForServer {
    Write-Host '[run.ps1] waiting for callgraph-server on :8080 ' -NoNewline
    for ($i = 0; $i -lt 150; $i++) {
        $code = Get-ServerCode
        if ($code -match '^[1-5][0-9]{2}$') { Write-Host " up (HTTP $code)"; return }
        Write-Host '.' -NoNewline
        Start-Sleep -Seconds 2
    }
    Write-Host ''
    Die "the server did not come up within 300s. Check: docker logs $Name"
}

function Invoke-Build {
    & docker build -t $Image $Root
    if ($LASTEXITCODE -ne 0) { Die 'docker build failed' }
}

function Invoke-Up {
    Require-Env
    if (Test-ContainerExists) {
        $running = & docker inspect -f '{{.State.Running}}' $Name 2>$null
        if ("$running" -eq 'true') { Log "container '$Name' is already running"; return }
        Log "starting existing container '$Name'"
        & docker start $Name | Out-Null
        if ($LASTEXITCODE -ne 0) { Die "docker start failed for '$Name'" }
    } else {
        Log "creating container '$Name' (image $Image)"
        & docker run -d --name $Name `
            -p 8080:8080 -p 7474:7474 -p 7687:7687 `
            --env-file "$Root\.env" `
            -v "${VolData}:/data" `
            -v "${VolLogs}:/logs" `
            -v "${VolClone}:/opt/change_impact_detector" `
            -v "${RootFwd}:/work" `
            $Image | Out-Null
        if ($LASTEXITCODE -ne 0) { Die "docker run failed for '$Name'" }
    }
    Wait-ForServer
    Log 'Neo4j Browser:    http://localhost:7474  (login: NEO4J_USERNAME / NEO4J_PASSWORD from .env)'
    Log 'callgraph-server: http://localhost:8080'
}

function Invoke-Status {
    Require-Container
    $state = & docker inspect -f '{{.State.Status}} (health: {{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}})' $Name
    Log "container: $Name - $state"
    $code = Get-ServerCode
    Log "callgraph-server :8080 -> HTTP $code (any 1xx-5xx code means it is listening)"
    if ($code -match '^[1-5][0-9]{2}$') { Invoke-Neo4jStats }
}

function Invoke-Neo4jStats {
    # Same three queries as the recorded Section 2 step 4
    # (results/raw/callgraph_stats.txt). Runs from the host over the
    # published Bolt port. All three statements travel as ONE argument:
    # cypher-shell 5.3.0 accepts exactly ONE positional cypher argument
    # (its usage line shows [cypher]) and rejects further positionals with
    # 'unrecognized arguments' - verified against the real 5.3.0 binary.
    Require-Container
    Require-Env
    $map = Get-DotEnv
    $u = $map['NEO4J_USERNAME']
    if (-not $u) { $u = 'neo4j' }
    $p = $map['NEO4J_PASSWORD']
    if (-not $p) { Die 'NEO4J_PASSWORD not found in .env' }
    & docker exec $Name cypher-shell -a bolt://localhost:7687 -u $u -p $p `
        'MATCH (f:Function) RETURN count(f) AS functions; MATCH ()-[r:CALLS]->() RETURN count(r) AS calls; MATCH (f:Function) WHERE f.pagerank IS NOT NULL RETURN count(f) AS withPagerank, sum(f.pagerank) AS pagerankSum;'
    if ($LASTEXITCODE -ne 0) {
        Die "Neo4j stats failed - is the database up yet? (docker logs $Name)"
    }
}

function Invoke-CreateSave {
    # Docker equivalent of the recorded Section 2 step 2 (the PowerShell
    # Invoke-RestMethod POST). Runs from the host over the published :8080,
    # body identical to the recorded one.
    Require-Container
    Require-Env
    $map = Get-DotEnv
    $token = $map['GITHUB_TOKEN']
    if (-not $token) { Die 'GITHUB_TOKEN not found in .env' }
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir = Join-Path $Root 'results\raw'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $out = Join-Path $dir ("create_save_response_docker_{0}.txt" -f $ts)
    Log 'posting create-save (clone + call graph + PageRank; takes a few minutes) ...'
    $body = @{
        projectIdentifier = 'arduino/Arduino'
        branchName        = 'master'
        githubToken       = $token
    } | ConvertTo-Json
    try {
        $resp = Invoke-WebRequest -UseBasicParsing `
            -Method Post `
            -Uri 'http://localhost:8080/api/v1/callgraph/create-save' `
            -ContentType 'application/json' -Body $body -TimeoutSec 0
        $text = "$($resp.Content)"
    } catch {
        Die "create-save failed: $($_.Exception.Message) (hint: docker logs $Name)"
    }
    $text | Out-File -FilePath $out -Encoding utf8
    Log "response saved to results\raw\create_save_response_docker_$ts.txt (empty response would mean failure)"
    Write-Host $text
    if (-not $text.Trim()) { Die 'empty response - that means failure' }
    Log 'expected: /opt/change_impact_detector/analyzed_repositories/arduino/Arduino'
}

function Invoke-CloneHead {
    # Docker equivalent of the recorded Section 2 step 3 (expect
    # a0df6e0e83b652c72bc78b0a1376c54d6ebc3bee).
    Require-Container
    & docker exec $Name git -C $CloneInContainer rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { Die 'git rev-parse failed' }
}

function Invoke-FetchPrBranches {
    # Docker equivalent of the recorded Section 4 step 1: fetch the PR head
    # branches whose new file versions are missing from the clone
    # (execution repair only; the clone stays on master, graph unchanged).
    param([string[]]$Refs = @())
    Require-Container
    if ($Refs.Count -eq 0) { $Refs = $DefaultPrBranches }
    $refArgs = @()
    foreach ($p in $Refs) {
        $refArgs += ("+refs/pull/{0}/head:refs/remotes/origin/pr/{1}" -f $p, $p)
    }
    & docker exec $Name git -C $CloneInContainer fetch origin @refArgs
    if ($LASTEXITCODE -ne 0) { Die 'git fetch failed' }
    Log "fetched $($Refs.Count) PR branch(es); clone HEAD unchanged:"
    Invoke-CloneHead
}

function Invoke-Fetch {
    param([string[]]$Passthrough = @())
    Require-Container
    & docker exec $Name python3 scripts/fetch_pr_data.py @Passthrough
    if ($LASTEXITCODE -ne 0) { Die 'fetch_pr_data.py failed' }
}

function Invoke-Query {
    param([string[]]$Passthrough = @())
    Require-Container
    & docker exec $Name python3 scripts/query_callgraph.py @Passthrough
    if ($LASTEXITCODE -ne 0) { Die 'query_callgraph.py failed' }
}

function Invoke-Metrics {
    param([string[]]$Passthrough = @())
    Require-Container
    & docker exec $Name python3 scripts/compute_metrics.py @Passthrough
    if ($LASTEXITCODE -ne 0) { Die 'compute_metrics.py failed' }
}

function Invoke-Selftest {
    Require-Container
    & docker exec $Name python3 scripts/compute_metrics.py --selftest
    if ($LASTEXITCODE -ne 0) { Die 'selftest failed' }
}

function Invoke-Logs {
    param([string[]]$Passthrough = @())
    Require-Container
    & docker logs @Passthrough $Name
}

function Invoke-SaveLogs {
    Require-Container
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir = Join-Path $Root 'Logs'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $out = Join-Path $dir ("callgraph_server_docker_{0}.log" -f $ts)
    & docker logs --timestamps $Name 2>&1 | ForEach-Object { "$_" } | Out-File -FilePath $out -Encoding utf8
    Log "container log saved to Logs\callgraph_server_docker_$ts.log"
}

function Invoke-Shell {
    Require-Container
    & docker exec -it $Name bash
}

function Invoke-Stop {
    Require-Container
    & docker stop $Name | Out-Null
    Log "stopped '$Name' (graph and clone kept)"
}

function Invoke-Start {
    Require-Container
    & docker start $Name | Out-Null
    Wait-ForServer
}

function Invoke-Restart { Invoke-Stop; Invoke-Start }

function Invoke-Down {
    Require-Container
    & docker rm -f $Name | Out-Null
    Log "removed '$Name' (named volumes kept: $VolData $VolLogs $VolClone)"
}

function Invoke-Destroy {
    & docker rm -f $Name 2>$null | Out-Null
    Write-Host "[run.ps1] deleting volumes $VolData $VolLogs $VolClone - this erases the graph, its logs and the clone. Type YES to confirm: " -NoNewline
    $ans = Read-Host
    if ($ans -cne 'YES') { Log 'aborted'; return }
    & docker volume rm $VolData $VolLogs $VolClone 2>$null | Out-Null
    Log 'volumes deleted'
}

function Invoke-Help {
    $t = @'
Usage: powershell -ExecutionPolicy Bypass -File docker\run.ps1 <command> [args...]

Setup
  build              Build the image (downloads the figshare artefact, applies the
                     Linux path patch, builds callgraph-server, pins Neo4j plugins)
  up                 Create/start the container and wait until :8080 answers
                     (ports 8080 7474 7687; bind-mounts the project at /work;
                     named volumes keep the Neo4j graph, its logs and the clone)
  status             Container health + the Section 2 graph-size queries
  shell              Open a bash shell inside the container

Recorded procedure equivalents (Notes/run_procedure.md)
  create-save        Section 2 step 2 - POST /api/v1/callgraph/create-save
                     (clone arduino/Arduino @ master, build call graph, PageRank)
  clone-head         Section 2 step 3 - git rev-parse HEAD of the clone (expect
                     a0df6e0e83b652c72bc78b0a1376c54d6ebc3bee)
  neo4j-stats        Section 2 step 4 - Function/CALLS/PageRank counts
  fetch [group]      Section 2        - python scripts/fetch_pr_data.py [group]
  selftest           Section 3        - compute_metrics.py --selftest (Fig. 10: 44.38, C)
  query <n|--all>    Section 3/4      - python scripts/query_callgraph.py ...
  metrics <n|--all>  Section 3/4      - python scripts/compute_metrics.py ...
  fetch-pr-branches [PR...]
                     Section 4 step 1 - git fetch of the PR head branches
                     (default: 8600 8607 8621 8640 8647)

Operations
  logs [docker-logs-args]   Follow/print container logs (Neo4j + server)
  save-logs                 Write container logs to Logs\callgraph_server_docker_<ts>.log
  stop | start | restart    Stop/start without deleting anything
  down                      Remove the container (named volumes are kept)
  destroy                   Remove the container AND the named volumes (erases the graph)

Environment
  CG_IMAGE, CG_CONTAINER, CG_VOL_DATA, CG_VOL_LOGS, CG_VOL_CLONE override
  defaults (set them with $env:CG_IMAGE etc. before calling). .env (copied
  from .env.example) must exist before 'up'.

Windows notes
  Runs on the preinstalled Windows PowerShell 5.1 or PowerShell 7 - no bash
  needed. create-save and neo4j-stats run from the host over the published
  ports, mirroring the original recorded PowerShell procedure.
'@
    Write-Host $t
}

$cmd = 'help'
$rest = @()
if ($args.Count -gt 0) { $cmd = $args[0] }
if ($args.Count -gt 1) { $rest = @($args[1..($args.Count - 1)]) }

switch ($cmd) {
    'build'             { Invoke-Build }
    'up'                { Invoke-Up }
    'status'            { Invoke-Status }
    'neo4j-stats'       { Invoke-Neo4jStats }
    'create-save'       { Invoke-CreateSave }
    'clone-head'        { Invoke-CloneHead }
    'fetch-pr-branches' { Invoke-FetchPrBranches -Refs ([string[]]$rest) }
    'fetch'             { Invoke-Fetch -Passthrough $rest }
    'query'             { Invoke-Query -Passthrough $rest }
    'metrics'           { Invoke-Metrics -Passthrough $rest }
    'selftest'          { Invoke-Selftest }
    'logs'              { Invoke-Logs -Passthrough $rest }
    'save-logs'         { Invoke-SaveLogs }
    'shell'             { Invoke-Shell }
    'stop'              { Invoke-Stop }
    'start'             { Invoke-Start }
    'restart'           { Invoke-Restart }
    'down'              { Invoke-Down }
    'destroy'           { Invoke-Destroy }
    'help'              { Invoke-Help }
    default             { Die "unknown command '$cmd'. See: powershell -ExecutionPolicy Bypass -File docker\run.ps1 help" }
}
