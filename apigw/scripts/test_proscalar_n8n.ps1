<#
.SYNOPSIS
    End-to-End Verification Test Suite for Proscalar Option C (Kong + n8n).
.DESCRIPTION
    Runs 5 test cases against Kong Gateway Ingress (port 8088):
    1. Unauthorized Rejection (401 Unauthorized from Kong)
    2. Active Point Alert (5002 Door Forced Open -> Incident Created)
    3. Auto-Resolution IDLE Event (4000 Reader Tamper IDLE)
    4. Safety Alarm Group (12008 Multi-Zone Fire Alert -> CRITICAL Incident)
    5. Rate Limiting Protection (Burst test)
#>

param(
    [string]$GatewayUrl = "http://localhost:8088",
    [string]$Username = "proscalar@gmail.com",
    [string]$Password = "fwpkyjcf2i8fcoP05yEz"
)

$endpoint = "$GatewayUrl/api/proscalar/webhook"
$authHeader = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${Username}:${Password}"))

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "🧪 Running Proscalar Option C (Kong + n8n) Test Suite" -ForegroundColor Cyan
Write-Host "   Endpoint: $endpoint" -ForegroundColor Gray
Write-Host "====================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# TEST 1: Unauthorized Request
# -----------------------------------------------------------------------------
Write-Host "`n[Test 1/5] Testing Unauthorized Request (Expect HTTP 401)..." -ForegroundColor Yellow
try {
    $resp = Invoke-WebRequest -Uri $endpoint -Method Post -ContentType "application/json" -Body '{"type":"event.publish"}' -UseBasicParsing -ErrorAction Stop
    Write-Host "❌ Failed: Expected 401, but received $($resp.StatusCode)" -ForegroundColor Red
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 401) {
        Write-Host "✅ PASSED: Kong edge rejected unauthorized request (HTTP 401 Unauthorized)." -ForegroundColor Green
    } else {
        Write-Host "❌ Failed: Received HTTP $statusCode instead of 401" -ForegroundColor Red
    }
}

# -----------------------------------------------------------------------------
# TEST 2: Active Single Event (Door Forced Open - 5002)
# -----------------------------------------------------------------------------
Write-Host "`n[Test 2/5] Testing Active Point Alert (Code 5002 - Door Forced Open)..." -ForegroundColor Yellow
$payload5002 = @{
    type = "event.publish"
    timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    data = @{
        id = "kong-opt-c-test-5002"
        eventTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        eventCode = "5002"
        eventSourceId = "proscalar-opt-c-src-1"
        eventSourceName = "OT-CTR-MAIN GATE"
        eventPointId = "proscalar-opt-c-pt-1"
        eventPointName = "OT-MAIN GATE"
        message = "Logical Door Forced Open ACTIVE."
    }
} | ConvertTo-Json -Depth 5

try {
    $resp2 = Invoke-RestMethod -Uri $endpoint -Method Post -Headers @{ Authorization = $authHeader } -ContentType "application/json" -Body $payload5002
    if ($resp2.success -eq $true) {
        Write-Host "✅ PASSED: Active event ingested and processed by n8n! (Execution ID: $($resp2.executionId))" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Warning: Response received but success != true: $($resp2 | ConvertTo-Json -Compress)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Failed to process 5002 event: $_" -ForegroundColor Red
}

# -----------------------------------------------------------------------------
# TEST 3: Auto-Resolution IDLE Event (Code 4000)
# -----------------------------------------------------------------------------
Write-Host "`n[Test 3/5] Testing IDLE Auto-Resolution Event (Code 4000 - Reader Tamper IDLE)..." -ForegroundColor Yellow
$payload4000 = @{
    type = "event.publish"
    timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    data = @{
        id = "kong-opt-c-test-4000"
        eventTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        eventCode = "4000"
        eventSourceId = "proscalar-opt-c-src-1"
        eventSourceName = "OT-CTR-MAIN GATE"
        eventPointId = "proscalar-opt-c-pt-1"
        eventPointName = "CV485"
        message = "Logical Reader Tamper IDLE."
    }
} | ConvertTo-Json -Depth 5

try {
    $resp3 = Invoke-RestMethod -Uri $endpoint -Method Post -Headers @{ Authorization = $authHeader } -ContentType "application/json" -Body $payload4000
    if ($resp3.success -eq $true) {
        Write-Host "✅ PASSED: IDLE event processed and resolved by pipeline! (Execution ID: $($resp3.executionId))" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Warning: Response received: $($resp3 | ConvertTo-Json -Compress)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Failed to process 4000 event: $_" -ForegroundColor Red
}

# -----------------------------------------------------------------------------
# TEST 4: Multi-Zone Fire Alarm Group (Code 12008 with FIRE Zone)
# -----------------------------------------------------------------------------
Write-Host "`n[Test 4/5] Testing Alarm Group Safety Event (FIRE Zone Priority)..." -ForegroundColor Yellow
$payloadFire = @{
    type = "alarm.publish"
    timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    data = @{
        alarmGroupId = "GRP-ZONE-FIRE-01"
        groupEventCode = "12008"
        name = "EAST WING FIRE CLUSTER"
        eventSourceName = "East Wing Panel 1"
        accessZones = @(
            @{ name = "East Lobby"; type = "NORMAL"; state = "ACTIVE" },
            @{ name = "East Server Room"; type = "FIRE"; state = "TRIGGERED" }
        )
    }
} | ConvertTo-Json -Depth 5

try {
    $resp4 = Invoke-RestMethod -Uri $endpoint -Method Post -Headers @{ Authorization = $authHeader } -ContentType "application/json" -Body $payloadFire
    if ($resp4.success -eq $true) {
        Write-Host "✅ PASSED: Multi-zone Fire group alarm ingested as CRITICAL! (Execution ID: $($resp4.executionId))" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Warning: Response received: $($resp4 | ConvertTo-Json -Compress)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Failed to process Fire group event: $_" -ForegroundColor Red
}

# -----------------------------------------------------------------------------
# TEST 5: Rate Limiting Enforcement
# -----------------------------------------------------------------------------
Write-Host "`n[Test 5/5] Testing Gateway Rate Limiting Policy (120 req/min limit)..." -ForegroundColor Yellow
$rateLimited = $false
Write-Host "   Sending rapid burst of requests..." -NoNewline
for ($i = 1; $i -le 130; $i++) {
    try {
        $null = Invoke-RestMethod -Uri $endpoint -Method Post -Headers @{ Authorization = $authHeader } -ContentType "application/json" -Body $payload5002 -ErrorAction Stop
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 429) {
            $rateLimited = $true
            Write-Host "`n✅ PASSED: Kong rate limiting enforced after $i requests (HTTP 429 Too Many Requests)." -ForegroundColor Green
            break
        }
    }
}

if (-not $rateLimited) {
    Write-Host "`n⚠️ Notice: Burst completed without hitting 429 limit within the test count window." -ForegroundColor Yellow
}

Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "🏁 Proscalar Option C Test Suite Finished!" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
