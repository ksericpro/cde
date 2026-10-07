<#
.SYNOPSIS
    Manual Test Runner for all 6 Proscalar Webhook Scenarios (Postman Collection).
.DESCRIPTION
    Sends the exact 6 vendor webhook payloads from docs/imops_proscalar.json to Kong Gateway:
    1. Door Forced Open (Code 5002 - Active Access Alarm)
    2. Reader Tamper (Code 4001 - Active Tamper Alarm)
    3. Reader Tamper Idle (Code 4000 - Auto-Resolve Tamper Alarm)
    4. Fire Alarm Group (Code 12008 - Safety / Fire Aggregation)
    5. AC Power Failure (Code 1000 - System & Hardware Alarm)
    6. Emergency Door Release (Code 5014 - Critical Safety Button)
#>

param(
    [Parameter(Position = 0)]
    [string]$Scenario = "all",

    [string]$GatewayUrl = "http://localhost:8088",
    [string]$Username = "proscalar@gmail.com",
    [string]$Password = "fwpkyjcf2i8fcoP05yEz"
)

$endpoint = "$GatewayUrl/api/proscalar/webhook"
$authHeader = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${Username}:${Password}"))
$headers = @{
    Authorization = $authHeader
    "Content-Type" = "application/json"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 6 EXACT PAYLOAD DEFINITIONS (From docs/imops_proscalar.json)
# ═══════════════════════════════════════════════════════════════════════════════

$scenarios = [ordered]@{
    "1" = @{
        Title = "1. Door Forced Open (Active Access Alarm)"
        Code = "5002"
        Expected = "High Severity Incident Created ('Door Force Opened')"
        Body = @'
{
  "type": "event.publish",
  "timestamp": "2026-06-09T03:00:00.000Z",
  "data": {
    "id": "mock-access-event-id",
    "eventTimestamp": "2026-06-09T02:59:58.000Z",
    "eventCode": "5002",
    "eventSourceId": "proscalar-test-source-id",
    "eventSourceName": "OT-CTR-MAIN GATE",
    "eventPointId": "proscalar-test-point-id",
    "eventPointName": "OT-MAIN GATE",
    "message": "Logical Door Forced Open ACTIVE.",
    "receivedTimestamp": "2026-06-09T02:59:59Z"
  }
}
'@
    }

    "2" = @{
        Title = "2. Reader Tamper (Active Tamper Alarm)"
        Code = "4001"
        Expected = "High Severity Incident Created ('Reader Tamper')"
        Body = @'
{
  "type": "event.publish",
  "timestamp": "2026-06-09T03:05:00.000Z",
  "data": {
    "id": "mock-tamper-event-id",
    "eventTimestamp": "2026-06-09T03:04:58.000Z",
    "eventCode": "4001",
    "eventSourceId": "proscalar-test-source-id",
    "eventSourceName": "178",
    "eventPointId": "proscalar-test-point-id",
    "eventPointName": "CV485",
    "message": "Logical Reader Tamper ACTIVE.",
    "receivedTimestamp": "2026-06-09T03:04:59Z"
  }
}
'@
    }

    "3" = @{
        Title = "3. Reader Tamper Idle (Auto-Resolve Code 4001)"
        Code = "4000"
        Expected = "Auto-resolves open Reader Tamper incident (No new alarm card)"
        Body = @'
{
  "type": "event.publish",
  "timestamp": "2026-06-09T03:10:00.000Z",
  "data": {
    "id": "mock-tamper-idle-id",
    "eventTimestamp": "2026-06-09T03:09:58.000Z",
    "eventCode": "4000",
    "eventSourceId": "proscalar-test-source-id",
    "eventSourceName": "178",
    "eventPointId": "proscalar-test-point-id",
    "eventPointName": "CV485",
    "message": "Logical Reader Tamper IDLE.",
    "receivedTimestamp": "2026-06-09T03:09:59Z"
  }
}
'@
    }

    "4" = @{
        Title = "4. Fire Alarm Group (Multi-Zone Fire Aggregation)"
        Code = "12008"
        Expected = "CRITICAL Incident Created ('Fire Alarm' - Safety Override)"
        Body = @'
{
  "type": "alarm.publish",
  "timestamp": "2026-06-09T03:15:00.000Z",
  "data": {
    "alarmGroupId": "mock-alarm-group-id-99",
    "groupEventCode": "12008",
    "name": "FIRE SIGNAL ALARM GROUP",
    "msg": "Alarm Monitoring Group Alarm. Alarm Zone OT-OPEN AREA",
    "eventSourceId": "proscalar-test-source-id",
    "eventSourceName": "OT-CTR-DOOR 1",
    "eventTimestamp": "2026-06-09T03:14:58.000Z",
    "accessZones": [
      {
        "alarmZoneId": "mock-zone-id-a",
        "name": "ZONE A",
        "type": "FIRE",
        "state": "TRIGGERED",
        "eventCode": "12000"
      },
      {
        "alarmZoneId": "mock-zone-id-b",
        "name": "ZONE B",
        "type": "INSTANT",
        "state": "TRIGGERED",
        "eventCode": "12000"
      }
    ]
  }
}
'@
    }

    "5" = @{
        Title = "5. AC Power Failure (Hardware Alarm)"
        Code = "1000"
        Expected = "High Severity Incident Created ('Power Failure')"
        Body = @'
{
  "type": "event.publish",
  "timestamp": "2026-06-09T03:20:00.000Z",
  "data": {
    "id": "mock-power-failure-id",
    "eventTimestamp": "2026-06-09T03:19:58.000Z",
    "eventCode": "1000",
    "eventSourceId": "proscalar-test-source-id",
    "eventSourceName": "OT-CTR-MAIN GATE",
    "eventPointId": "proscalar-test-point-id",
    "eventPointName": "Main Enclosure Power",
    "message": "Controller AC Power Failure ACTIVE.",
    "receivedTimestamp": "2026-06-09T03:19:59Z"
  }
}
'@
    }

    "6" = @{
        Title = "6. Emergency Door Release (Device-Level Safety Button)"
        Code = "5014"
        Expected = "CRITICAL Incident Created ('Emergency Exit Opened')"
        Body = @'
{
  "type": "event.publish",
  "timestamp": "2026-06-09T03:25:00.000Z",
  "data": {
    "id": "mock-emergency-release-id",
    "eventTimestamp": "2026-06-09T03:24:58.000Z",
    "eventCode": "5014",
    "eventSourceId": "proscalar-test-source-id",
    "eventSourceName": "OT-CTR-MAIN GATE",
    "eventPointId": "proscalar-test-point-id",
    "eventPointName": "EMERGENCY DOOR RELEASE BUTTON",
    "message": "Emergency Exit Button Pressed ACTIVE.",
    "receivedTimestamp": "2026-06-09T03:24:59Z"
  }
}
'@
    }
}

function Invoke-SingleScenario($key) {
    $item = $scenarios[$key]
    Write-Host ""
    Write-Host "----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("SENDING: " + $item.Title) -ForegroundColor Cyan
    Write-Host ("Event Code: " + $item.Code) -ForegroundColor Gray
    Write-Host ("Expected:   " + $item.Expected) -ForegroundColor Yellow
    
    try {
        $resp = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body $item.Body
        Write-Host "Status:     [PASSED] HTTP 200 OK" -ForegroundColor Green
        if ($resp.pipeline) {
            Write-Host ("Pipeline:   " + $resp.pipeline) -ForegroundColor Gray
        }
        if ($resp.executionId) {
            Write-Host ("Exec ID:    " + $resp.executionId) -ForegroundColor Green
        }
        if ($resp.message) {
            Write-Host ("Result:     " + $resp.message) -ForegroundColor Green
        }
    } catch {
        Write-Host ("Status:     [FAILED] " + $_.Exception.Message) -ForegroundColor Red
        if ($_.Exception.Response) {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            Write-Host ("Details:    " + $reader.ReadToEnd()) -ForegroundColor Red
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Proscalar Ingress Test Suite (imops_proscalar.json)" -ForegroundColor Cyan
Write-Host ("Endpoint:   " + $endpoint) -ForegroundColor Gray
Write-Host "Target:     Kong Edge Gateway (Port 8088)" -ForegroundColor Gray
Write-Host "====================================================" -ForegroundColor Cyan

if ($Scenario -eq "all") {
    foreach ($k in $scenarios.Keys) {
        Invoke-SingleScenario $k
        Start-Sleep -Milliseconds 300
    }
} elseif ($scenarios.Contains($Scenario)) {
    Invoke-SingleScenario $Scenario
} else {
    Write-Host "Please specify scenario 1, 2, 3, 4, 5, 6, or 'all'." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Finished! View executions at https://localhost:5678" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
