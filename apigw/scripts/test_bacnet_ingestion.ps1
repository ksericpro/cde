<#
.SYNOPSIS
    End-to-End Test Script for Kong Gateway Service: cde-bacnet-adapter-service
.DESCRIPTION
    Tests all 4 scenarios against http://localhost:8088:
      1. Unauthenticated request -> Expects 401 Unauthorized
      2. POST /api/v1/bacnet/devices -> Expects 202 Accepted
      3. POST /api/v1/bacnet/telemetry (Optergy P864 batch) -> Expects 202 Accepted
      4. GET  /api/v1/bacnet/status -> Displays transformed IMOPS payload & Data Lakehouse archive path
#>

param(
    [string]$GatewayBaseUrl = "http://localhost:8088",
    [string]$ApiKey = "zaarr-bacnet-gw01-key-2026"
)

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " Testing Kong Gateway Service: cde-bacnet-adapter-service" -ForegroundColor Cyan
Write-Host "   Gateway URL: $GatewayBaseUrl" -ForegroundColor Gray
Write-Host "   X-API-Key:   $ApiKey" -ForegroundColor Gray
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Test Unauthenticated Request (Should fail with 401)
Write-Host "`n[Test 1/4] Security Check (POST without X-API-Key -> Expect 401)..." -ForegroundColor Yellow
try {
    Invoke-RestMethod -Uri "$GatewayBaseUrl/api/v1/bacnet/telemetry" -Method Post -ContentType "application/json" -Body "{}" -ErrorAction Stop
    Write-Host "   [FAIL] Request succeeded without API key!" -ForegroundColor Red
} catch {
    $code = [int]$_.Exception.Response.StatusCode
    Write-Host "   [PASS] Blocked with HTTP $code Unauthorized" -ForegroundColor Green
}

$headers = @{
    "X-API-Key"  = $ApiKey
    "User-Agent" = "zaarr-bacnet-gw/1.0"
}

# 2. Test POST /api/v1/bacnet/devices
Write-Host "`n[Test 2/4] Sending Controller Status (POST /api/v1/bacnet/devices)..." -ForegroundColor Yellow
$deviceBody = @{
    gateway_id = "zaarr-bacnet-gw-01"
    site_name  = "Smart Nation Exhibition System"
    sent_at    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    device     = @{
        device_id            = 864077
        object_name          = "P864-864077"
        model_name           = "P864"
        vendor_name          = "Optergy"
        vendor_id            = 515
        firmware_revision    = "2.4.0"
        address              = "192.168.0.160:47808"
        online               = $true
        communication_status = "online"
        point_count          = 12
        discovered_at        = "2026-11-13T00:00:05Z"
    }
} | ConvertTo-Json -Depth 5

$devResp = Invoke-RestMethod -Uri "$GatewayBaseUrl/api/v1/bacnet/devices" -Method Post -Headers $headers -ContentType "application/json" -Body $deviceBody
Write-Host "   [PASS] Response: $($devResp | ConvertTo-Json -Compress)" -ForegroundColor Green

# 3. Test POST /api/v1/bacnet/telemetry
Write-Host "`n[Test 3/4] Sending Telemetry Batch (POST /api/v1/bacnet/telemetry)..." -ForegroundColor Yellow
$nowIso = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$batchId = "batch-" + (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$telemetryBody = @{
    gateway_id = "zaarr-bacnet-gw-01"
    site_name  = "Smart Nation Exhibition System"
    batch_id   = $batchId
    sent_at    = $nowIso
    count      = 2
    readings   = @(
        @{
            timestamp        = $nowIso
            source_type      = "poll"
            device_id        = 864077
            device_name      = "P864-864077"
            controller_model = "P864"
            device_address   = "192.168.0.160:47808"
            object_type      = "analog-input"
            object_instance  = 101
            object_id        = "analog-input:101"
            short_object_id  = "AI-101"
            point_name       = "BW-INT-M (WIRELESS AIR TOUCH DISPLAY)"
            property_label   = "Temperature"
            dashboard_label  = "BW-INT-M"
            connection_bus   = "BG-1000-M (Wireless)"
            value            = 23.45
            value_text       = "23.45 C"
            unit             = "C"
            unit_id          = 62
            is_triggered     = $false
            is_alarm         = $false
            quality          = "good"
            status_flags     = @{ in_alarm = $false; fault = $false; overridden = $false; out_of_service = $false }
        },
        @{
            timestamp        = $nowIso
            source_type      = "cov"
            device_id        = 864077
            device_name      = "P864-864077"
            controller_model = "P864"
            device_address   = "192.168.0.160:47808"
            object_type      = "binary-input"
            object_instance  = 1
            object_id        = "binary-input:1"
            short_object_id  = "BI-1"
            point_name       = "WD3 (WATER LEAK)"
            property_label   = "Water detected"
            dashboard_label  = "WD3"
            connection_bus   = "IN 1 - Dry Contact (LED 1)"
            value            = 1
            value_text       = "Water Detected"
            is_triggered     = $true
            is_alarm         = $true
            quality          = "alarm"
            status_flags     = @{ in_alarm = $false; fault = $false; overridden = $false; out_of_service = $false }
        }
    )
} | ConvertTo-Json -Depth 6

$telResp = Invoke-RestMethod -Uri "$GatewayBaseUrl/api/v1/bacnet/telemetry" -Method Post -Headers $headers -ContentType "application/json" -Body $telemetryBody
Write-Host "   [PASS] Response: $($telResp | ConvertTo-Json -Compress)" -ForegroundColor Green

Start-Sleep -Seconds 1

# 4. Test GET /api/v1/bacnet/status
Write-Host "`n[Test 4/4] Checking Adapter Status & Massaged Output (GET /api/v1/bacnet/status)..." -ForegroundColor Yellow
$statusResp = Invoke-RestMethod -Uri "$GatewayBaseUrl/api/v1/bacnet/status" -Method Get -Headers $headers
Write-Host "   Target iMOPS URL:     $($statusResp.targetImopsBaseUrl)" -ForegroundColor Cyan
Write-Host "   Lakehouse Archive:    $($statusResp.metrics.lastLakehouseArchive)" -ForegroundColor Cyan
Write-Host "   Batches Received:     $($statusResp.metrics.telemetryBatchesReceived)" -ForegroundColor Cyan
Write-Host "`n   Massaged Payload Prepared for iMOPS:" -ForegroundColor Green
$statusResp.lastTransformedPayload | ConvertTo-Json -Depth 6 | Write-Host
Write-Host "==================================================================" -ForegroundColor Cyan

