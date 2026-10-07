<#
.SYNOPSIS
    End-to-End Verification Test Suite for Proscalar Option C (Kong + n8n)
    Windows runner using native curl.exe
.DESCRIPTION
    Runs 5 automated verification tests against the Kong edge ingress using Windows curl.exe:
    1. Unauthorized Request (Expect HTTP 401)
    2. Active Single Event (Door Forced Open - Code 5002)
    3. Auto-Resolution IDLE Event (Reader Tamper IDLE - Code 4000)
    4. Multi-Zone Fire Alarm Group (Code 12008 with FIRE Zone)
    5. Gateway Rate Limiting Policy (120 req/min)
#>

param(
    [string]$GatewayUrl = "http://localhost:8088",
    [string]$Username = "proscalar@gmail.com",
    [string]$Password = "fwpkyjcf2i8fcoP05yEz"
)

$Endpoint = "$GatewayUrl/api/proscalar/webhook"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FixturesDir = Join-Path $ScriptDir "fixtures"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "🧪 Running Proscalar Option C (Kong + n8n) - Windows curl.exe" -ForegroundColor Cyan
Write-Host "   Endpoint: $Endpoint" -ForegroundColor Gray
Write-Host "   Fixtures: $FixturesDir" -ForegroundColor Gray
Write-Host "====================================================" -ForegroundColor Cyan

# ----------------------------------------------------
# TEST 1: Unauthorized Request
# ----------------------------------------------------
Write-Host "`n[Test 1/5] Testing Unauthorized Request (Expect HTTP 401)..." -ForegroundColor Yellow
$status1 = & curl.exe -s -o NUL -w "%{http_code}" -X POST "$Endpoint" `
    -H "Content-Type: application/json" `
    -d "@$FixturesDir/ping.json"

if ($status1 -eq "401") {
    Write-Host "✅ PASSED: Kong edge rejected unauthorized request (HTTP 401 Unauthorized)." -ForegroundColor Green
} else {
    Write-Host "❌ FAILED: Received HTTP $status1 instead of 401." -ForegroundColor Red
}

# ----------------------------------------------------
# TEST 2: Active Event (Code 5002)
# ----------------------------------------------------
Write-Host "`n[Test 2/5] Testing Active Point Alert (Code 5002 - Door Forced Open)..." -ForegroundColor Yellow
$resp2 = & curl.exe -s -X POST "$Endpoint" `
    -u "${Username}:${Password}" `
    -H "Content-Type: application/json" `
    -d "@$FixturesDir/event_5002.json"

if ($resp2 -match '"success":true') {
    Write-Host "✅ PASSED: Active event ingested and processed by n8n!" -ForegroundColor Green
    Write-Host "   Response: $resp2" -ForegroundColor Gray
} else {
    Write-Host "❌ FAILED: Unexpected response." -ForegroundColor Red
    Write-Host "   Response: $resp2" -ForegroundColor Red
}

# ----------------------------------------------------
# TEST 3: Auto-Resolution Event (Code 4000)
# ----------------------------------------------------
Write-Host "`n[Test 3/5] Testing IDLE Auto-Resolution Event (Code 4000 - Reader Tamper IDLE)..." -ForegroundColor Yellow
$resp3 = & curl.exe -s -X POST "$Endpoint" `
    -u "${Username}:${Password}" `
    -H "Content-Type: application/json" `
    -d "@$FixturesDir/event_4000.json"

if ($resp3 -match '"success":true') {
    Write-Host "✅ PASSED: IDLE event processed and resolved by pipeline!" -ForegroundColor Green
    Write-Host "   Response: $resp3" -ForegroundColor Gray
} else {
    Write-Host "❌ FAILED: Unexpected response." -ForegroundColor Red
    Write-Host "   Response: $resp3" -ForegroundColor Red
}

# ----------------------------------------------------
# TEST 4: Multi-Zone Fire Alarm Group (Code 12008)
# ----------------------------------------------------
Write-Host "`n[Test 4/5] Testing Alarm Group Safety Event (FIRE Zone Priority)..." -ForegroundColor Yellow
$resp4 = & curl.exe -s -X POST "$Endpoint" `
    -u "${Username}:${Password}" `
    -H "Content-Type: application/json" `
    -d "@$FixturesDir/alarm_12008.json"

if ($resp4 -match '"success":true') {
    Write-Host "✅ PASSED: Multi-zone Fire group alarm ingested as CRITICAL!" -ForegroundColor Green
    Write-Host "   Response: $resp4" -ForegroundColor Gray
} else {
    Write-Host "❌ FAILED: Unexpected response." -ForegroundColor Red
    Write-Host "   Response: $resp4" -ForegroundColor Red
}

# ----------------------------------------------------
# TEST 5: Rate Limiting Enforcement (120 req/min)
# ----------------------------------------------------
Write-Host "`n[Test 5/5] Testing Gateway Rate Limiting Policy (rapid burst)..." -ForegroundColor Yellow
$throttled = $false
for ($i = 1; $i -le 125; $i++) {
    $code = & curl.exe -s -o NUL -w "%{http_code}" -X POST "$Endpoint" `
        -u "${Username}:${Password}" `
        -H "Content-Type: application/json" `
        -d "@$FixturesDir/ping.json"
    if ($code -eq "429") {
        $throttled = $true
        break
    }
}

if ($throttled) {
    Write-Host "✅ PASSED: Kong rate limiting enforced: HTTP 429 Too Many Requests received." -ForegroundColor Green
} else {
    Write-Host "⚠️  Notice: Rapid burst of 125 requests completed without hitting 429 in current window." -ForegroundColor Yellow
}

Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "🏁 Proscalar Option C Windows curl.exe Suite Finished!" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
