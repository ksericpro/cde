# =============================================================================
#  deploy_monitoring.ps1 — Initialize and launch Grafana & Prometheus stack
# =============================================================================
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$grafanaDir = Split-Path -Parent $scriptDir

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Deploying CDE Monitoring Stack (Grafana + Prometheus)          " -ForegroundColor Cyan
Write-Host "  Directory: $grafanaDir                                         " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

Set-Location $grafanaDir

# 1. Ensure .env exists
if (-not (Test-Path ".env")) {
    Write-Host "[*] .env file not found. Copying from .env.example..." -ForegroundColor Yellow
    Copy-Item ".env.example" ".env"
}

# 2. Check / Create external network 'cde-network'
$netCheck = docker network ls --filter name=cde-network -q
if (-not $netCheck) {
    Write-Host "[+] Creating external Docker network 'cde-network'..." -ForegroundColor Yellow
    docker network create cde-network | Out-Null
} else {
    Write-Host "[+] Docker network 'cde-network' already exists." -ForegroundColor Green
}

# 3. Pull latest images and launch containers
Write-Host "[+] Starting containers via docker compose..." -ForegroundColor Yellow
docker compose up -d

Write-Host ""
Write-Host "[+] Monitoring stack deployed successfully!" -ForegroundColor Green
Write-Host "    - Grafana Web UI:       http://localhost:3000 (admin / cdepassword123)" -ForegroundColor Green
Write-Host "    - Prometheus Targets:   http://localhost:9090/targets" -ForegroundColor Green
Write-Host "    - Node Exporter:        http://localhost:9100/metrics" -ForegroundColor Green
Write-Host "    - cAdvisor:             http://localhost:8080/containers" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Cyan
