# =============================================================================
#  deploy_elk.ps1 — Deploy Elasticsearch, Logstash, Kibana, Filebeat
# =============================================================================
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$elkDir = Split-Path -Parent $scriptDir

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Deploying CDE Centralized Logging (ELK Stack)                  " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Check docker network
$netCheck = docker network ls --filter name=cde-network -q
if (-not $netCheck) {
    Write-Host "[+] Creating external Docker network 'cde-network'..." -ForegroundColor Yellow
    docker network create cde-network | Out-Null
}

# 2. Start stack
Write-Host "[+] Starting Elasticsearch, Logstash, Kibana, and Filebeat..." -ForegroundColor Yellow
docker compose -f "$elkDir\docker-compose.yml" up -d

Write-Host "[+] Waiting for Elasticsearch to be healthy (port 9200)..." -ForegroundColor Yellow
$maxRetries = 20
$retries = 0
$healthy = $false
while (-not $healthy -and $retries -lt $maxRetries) {
    try {
        $res = Invoke-RestMethod -Uri "http://localhost:9200/_cluster/health" -Method Get -TimeoutSec 3 -ErrorAction SilentlyContinue
        if ($res.status -in @("green", "yellow")) {
            $healthy = $true
            Write-Host "[+] Elasticsearch is ONLINE (Cluster Status: $($res.status), Nodes: $($res.number_of_nodes))" -ForegroundColor Green
        }
    } catch {
        Start-Sleep -Seconds 3
        $retries++
    }
}

if (-not $healthy) {
    Write-Host "[-] WARNING: Elasticsearch is taking longer than expected to initialize. Check 'docker logs cde-elasticsearch'" -ForegroundColor Yellow
}

Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host "  ELK Stack Deployed Successfully!                               " -ForegroundColor Green
Write-Host "  - Elasticsearch:  http://localhost:9200                        " -ForegroundColor White
Write-Host "  - Kibana UI:      http://localhost:5601                        " -ForegroundColor White
Write-Host "  - Logstash Beats: port 5044 (Filebeat)                         " -ForegroundColor White
Write-Host "  - Logstash TCP:   port 5000 (Kong tcp-log)                     " -ForegroundColor White
Write-Host "=================================================================" -ForegroundColor Cyan
