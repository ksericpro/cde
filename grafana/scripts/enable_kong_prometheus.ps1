# =============================================================================
#  enable_kong_prometheus.ps1 — Enable Prometheus Plugin globally on Kong Gateway
# =============================================================================
param(
    [string]$KongAdminUrl = "http://localhost:8001"
)

$ErrorActionPreference = "Stop"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Enabling Prometheus Metrics Plugin on Kong Gateway             " -ForegroundColor Cyan
Write-Host "  Target Admin API: $KongAdminUrl                                " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

try {
    $status = Invoke-RestMethod -Uri "$KongAdminUrl/status" -Method Get -TimeoutSec 5
    Write-Host "[+] Connected to Kong Gateway (Server: $($status.server.total_requests) total requests)" -ForegroundColor Green
} catch {
    Write-Host "[-] ERROR: Kong Admin API is not reachable at $KongAdminUrl" -ForegroundColor Red
    exit 1
}

# Check existing plugins
$plugins = Invoke-RestMethod -Uri "$KongAdminUrl/plugins" -Method Get
$existing = $plugins.data | Where-Object { $_.name -eq "prometheus" }

$body = @{
    "name" = "prometheus"
    "config.status_code_metrics" = "true"
    "config.latency_metrics" = "true"
    "config.bandwidth_metrics" = "true"
    "config.upstream_health_metrics" = "true"
}

if ($existing) {
    Write-Host "[+] Prometheus plugin already exists (ID: $($existing.id)). Updating configuration..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$KongAdminUrl/plugins/$($existing.id)" -Method Patch -Body $body | Out-Null
} else {
    Write-Host "[+] Enabling global Prometheus plugin..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$KongAdminUrl/plugins" -Method Post -Body $body | Out-Null
}

Write-Host "[+] Verifying /metrics scraping endpoint..." -ForegroundColor Yellow
$metricsRes = Invoke-WebRequest -Uri "$KongAdminUrl/metrics" -Method Get
if ($metricsRes.StatusCode -eq 200) {
    Write-Host "[+] SUCCESS: Kong /metrics endpoint responded with HTTP 200 OK." -ForegroundColor Green
} else {
    Write-Host "[-] WARNING: Received HTTP $($metricsRes.StatusCode) from $KongAdminUrl/metrics" -ForegroundColor Red
}

Write-Host "=================================================================" -ForegroundColor Cyan
