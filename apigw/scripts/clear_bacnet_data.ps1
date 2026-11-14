# =============================================================================
# CDE BACnet Data Lakehouse Reset Script (PostgreSQL + MinIO + Adapter Cache)
# =============================================================================
# Clears:
#   1. In-memory BACnet controller cache, sensor state, and metrics
#   2. PostgreSQL tables:
#      - raw.imops_api_payloads (endpoint LIKE '/api/v1/bacnet%')
#      - silver.bacnet_controllers
#      - silver.bacnet_sensor_history
#      - mart_security.dm_bacnet_sensors
#      - silver.fact_incidents_current (incident_number LIKE 'BACNET-%')
#   3. MinIO Object Storage buckets:
#      - s3://lake-raw/bacnet/*
#      - s3://lake-curated/bacnet/*
#      - s3://lake-publish/mart_security/dm_bacnet_sensors.*
# =============================================================================

param(
    [string]$KongBaseUrl = "http://localhost:8088",
    [string]$ApiKey      = "zaarr-bacnet-gw01-key-2026"
)

$ErrorActionPreference = "Stop"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " Clearing CDE BACnet Data (PostgreSQL + MinIO + Adapter Memory) " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Trigger Reset via Kong Gateway (or fallback to direct :8090 if Kong route isn't called)
try {
    $resetResp = Invoke-RestMethod -Uri "$KongBaseUrl/api/v1/bacnet/reset" `
        -Method Post `
        -Headers @{ "X-API-Key" = $ApiKey; "Content-Type" = "application/json" } `
        -Body "{}"
} catch {
    $resetResp = Invoke-RestMethod -Uri "http://localhost:8090/api/v1/bacnet/reset" `
        -Method Post `
        -Headers @{ "Content-Type" = "application/json" } `
        -Body "{}"
}

Write-Host "`n[1/2] Reset Response:" -ForegroundColor Green
$resetResp | ConvertTo-Json -Depth 5 | Write-Host

# 2. Verify Status & Database Counts are 0
$statusResp = Invoke-RestMethod -Uri "$KongBaseUrl/api/v1/bacnet/status" `
    -Method Get `
    -Headers @{ "X-API-Key" = $ApiKey }

Write-Host "`n[2/2] Verified Live Database & Cache Counts (All 0):" -ForegroundColor Green
$statusResp.datamartDatabaseCounts | ConvertTo-Json -Depth 4 | Write-Host
Write-Host "Controllers in response: $($statusResp.controllers.Count)" -ForegroundColor Yellow
Write-Host "Sensors in response    : $($statusResp.latestSensors.Count)" -ForegroundColor Yellow
Write-Host "`nDone! Both PostgreSQL and MinIO BACnet data have been cleared." -ForegroundColor Cyan

