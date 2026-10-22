# =============================================================================
#  enable_kong_logstash.ps1 — Enable Kong TCP Log Plugin to ship logs to Logstash
# =============================================================================
param(
    [string]$KongAdminUrl = "http://localhost:8001",
    [string]$LogstashHost = "cde-logstash",
    [int]$LogstashPort = 5000
)

$ErrorActionPreference = "Stop"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Enabling TCP Log Plugin on Kong Gateway for ELK Logstash       " -ForegroundColor Cyan
Write-Host "  Kong Admin:     $KongAdminUrl                                  " -ForegroundColor Cyan
Write-Host "  Logstash Host:  ${LogstashHost}:${LogstashPort}                    " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Verify Kong connectivity
try {
    $status = Invoke-RestMethod -Uri "$KongAdminUrl/status" -Method Get -TimeoutSec 5
    Write-Host "[+] Connected to Kong Gateway (Server: $($status.server.total_requests) requests handled)" -ForegroundColor Green
} catch {
    Write-Host "[-] ERROR: Kong Admin API is not reachable at $KongAdminUrl" -ForegroundColor Red
    exit 1
}

# 2. Check for existing tcp-log plugin
$plugins = Invoke-RestMethod -Uri "$KongAdminUrl/plugins" -Method Get
$existing = $plugins.data | Where-Object { $_.name -eq "tcp-log" }

$payload = @{
    name   = "tcp-log"
    config = @{
        host      = $LogstashHost
        port      = $LogstashPort
        tls       = $false
        timeout   = 10000
        keepalive = 60000
    }
} | ConvertTo-Json -Depth 5

if ($existing) {
    Write-Host "[+] tcp-log plugin already exists (ID: $($existing.id)). Updating target to ${LogstashHost}:${LogstashPort}..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$KongAdminUrl/plugins/$($existing.id)" -Method Patch -ContentType "application/json" -Body $payload | Out-Null
} else {
    Write-Host "[+] Enabling global tcp-log plugin shipping to ${LogstashHost}:${LogstashPort}..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$KongAdminUrl/plugins" -Method Post -ContentType "application/json" -Body $payload | Out-Null
}

Write-Host "[+] SUCCESS: Kong Gateway is now configured to ship real-time access logs to Logstash!" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Cyan
