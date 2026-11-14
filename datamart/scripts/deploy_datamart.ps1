# =============================================================================
#  deploy_datamart.ps1 — Deploy CDE Security Data Mart Storage Stack (Phase 1)
#  Starts PostgreSQL 16 (cde-datamart-db) and MinIO Object Store (cde-minio)
# =============================================================================
$ErrorActionPreference = "Continue"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$datamartDir = Split-Path -Parent $scriptDir

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Deploying CDE Security Data Mart Storage Stack (Phase 1)       " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Ensure external cde-network exists
$netCheck = docker network ls --filter name=cde-network -q
if (-not $netCheck) {
    Write-Host "[+] Creating external Docker network 'cde-network'..." -ForegroundColor Yellow
    docker network create cde-network | Out-Null
}

# 2. Launch PostgreSQL + MinIO containers
Write-Host "[+] Starting cde-datamart-db (PostgreSQL 16) and cde-minio..." -ForegroundColor Yellow
docker compose -f "$datamartDir\docker-compose.yml" up -d

# 3. Wait for PostgreSQL to be healthy and ensure DDL is applied
Write-Host "[+] Waiting for cde-datamart-db to accept connections..." -ForegroundColor Yellow
$retries = 0
$ready = $false
while (-not $ready -and $retries -lt 15) {
    $check = docker exec cde-datamart-db pg_isready -U cdeadmin -d cde_datamart 2>$null
    if ($LASTEXITCODE -eq 0) {
        $ready = $true
    } else {
        Start-Sleep -Seconds 2
        $retries++
    }
}

Write-Host "[+] Ensuring Medallion schemas and tables (raw, silver, mart_security) are initialized..." -ForegroundColor Yellow
Get-Content "$datamartDir\sql\01_init_schemas_and_tables.sql" -Raw | docker exec -i cde-datamart-db psql -U cdeadmin -d cde_datamart | Out-Null

# 4. Initialize the 3 Lakehouse buckets in MinIO (lake-raw, lake-curated, lake-publish)
Write-Host "[+] Initializing MinIO Lakehouse buckets (lake-raw, lake-curated, lake-publish)..." -ForegroundColor Yellow
docker exec cde-minio mkdir -p /data/lake-raw /data/lake-curated /data/lake-publish 2>$null

Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host "  Phase 1 Data Mart Storage Stack Deployed Successfully!         " -ForegroundColor Green
Write-Host "  - PostgreSQL DB:  localhost:5433 (DB: cde_datamart)            " -ForegroundColor White
Write-Host "  - MinIO S3 API:   http://localhost:9000                        " -ForegroundColor White
Write-Host "  - MinIO Console:  http://localhost:9001 (cdeadmin/cdepassword123)" -ForegroundColor White
Write-Host "=================================================================" -ForegroundColor Cyan
