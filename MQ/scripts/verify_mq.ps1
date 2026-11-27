# =============================================================================
#  verify_mq.ps1 — Smoke test Mosquitto (TCP + WebSockets + ACL) and Cedalo UI
# =============================================================================
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mqDir = Split-Path -Parent $scriptDir
Set-Location $mqDir

$envVars = @{}
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $idx = $line.IndexOf("=")
            $key = $line.Substring(0, $idx).Trim()
            $val = $line.Substring($idx + 1).Trim().Trim('"').Trim("'")
            $envVars[$key] = $val
        }
    }
}

function Get-EnvOrDefault([string]$key, [string]$defaultVal) {
    if ($envVars.ContainsKey($key) -and $envVars[$key] -ne "") { return $envVars[$key] }
    return $defaultVal
}

$mqttWsPort            = [int](Get-EnvOrDefault "MQTT_WS_PORT" "9002")
$mmcPort               = [int](Get-EnvOrDefault "MMC_PORT" "8089")
$mqttAdminUser         = Get-EnvOrDefault "MQTT_ADMIN_USER" "cedalo"
$mqttAdminPassword     = Get-EnvOrDefault "MQTT_ADMIN_PASSWORD" "cdepassword123"
$mqttPublisherUser     = Get-EnvOrDefault "MQTT_PUBLISHER_USER" "cde-publisher"
$mqttPublisherPassword = Get-EnvOrDefault "MQTT_PUBLISHER_PASSWORD" "cdepublisher123"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Verifying CDE Message Queue (Mosquitto + Cedalo MC)            " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

Write-Host "[1/5] Checking running containers..." -ForegroundColor Yellow
docker compose ps

Write-Host "[2/5] Verifying anonymous connections are REJECTED..." -ForegroundColor Yellow
$ErrorActionPreference = "Continue"
docker exec cde-mosquitto mosquitto_pub -h localhost -p 1883 -t "cde/test" -m "anon" *> $null
$anonRc = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($anonRc -eq 0) {
    Write-Host "[-] FAIL: Anonymous publish succeeded (should be denied)!" -ForegroundColor Red
    exit 1
} else {
    Write-Host "[+] PASS: Anonymous connection rejected." -ForegroundColor Green
}

Write-Host "[3/5] Verifying per-topic Dynamic Security publish/subscribe..." -ForegroundColor Yellow
$testRole    = "verify-healthcheck-role"
$testUser    = "verify-healthcheck-sub"
$testPass    = "verify-tmp-pass-123"
$testPayload = "cde-healthcheck-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"

try {
    docker exec `
        -e "MQTT_ADMIN_USER=$mqttAdminUser" `
        -e "MQTT_ADMIN_PASSWORD=$mqttAdminPassword" `
        -e "TEST_ROLE=$testRole" `
        -e "TEST_USER=$testUser" `
        -e "TEST_PASS=$testPass" `
        cde-mosquitto sh -c '
            mosquitto_ctrl -h localhost -p 1883 -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec createRole "$TEST_ROLE" >/dev/null
            mosquitto_ctrl -h localhost -p 1883 -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec addRoleACL "$TEST_ROLE" subscribeLiteral "cde/healthcheck" allow >/dev/null
            mosquitto_ctrl -h localhost -p 1883 -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec createClient "$TEST_USER" -p "$TEST_PASS" >/dev/null
            mosquitto_ctrl -h localhost -p 1883 -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec addClientRole "$TEST_USER" "$TEST_ROLE" >/dev/null
        '

    $subJob = Start-Job -ScriptBlock {
        param($u, $p)
        docker exec cde-mosquitto mosquitto_sub -h localhost -p 1883 -u $u -P $p -t "cde/healthcheck" -C 1 -W 5 2>&1
    } -ArgumentList $testUser, $testPass

    Start-Sleep -Seconds 1
    docker exec cde-mosquitto mosquitto_pub -h localhost -p 1883 -u $mqttPublisherUser -P $mqttPublisherPassword -t "cde/healthcheck" -m $testPayload

    Wait-Job $subJob -Timeout 8 | Out-Null
    $received = ((Receive-Job $subJob) -join "`n").Trim()
    Remove-Job $subJob -Force -ErrorAction SilentlyContinue

    if ($received -eq $testPayload) {
        Write-Host "[+] PASS: Published with '$mqttPublisherUser' & received '$received' with topic-scoped subscriber." -ForegroundColor Green
    } else {
        Write-Host "[-] FAIL: Expected '$testPayload', got '$received'" -ForegroundColor Red
        exit 1
    }
} finally {
    $ErrorActionPreference = "Continue"
    docker exec `
        -e "MQTT_ADMIN_USER=$mqttAdminUser" `
        -e "MQTT_ADMIN_PASSWORD=$mqttAdminPassword" `
        -e "TEST_ROLE=$testRole" `
        -e "TEST_USER=$testUser" `
        cde-mosquitto sh -c '
            mosquitto_ctrl -h localhost -p 1883 -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec deleteClient "$TEST_USER" >/dev/null 2>&1 || true
            mosquitto_ctrl -h localhost -p 1883 -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec deleteRole "$TEST_ROLE" >/dev/null 2>&1 || true
        ' *> $null
    $ErrorActionPreference = "Stop"
}

Write-Host "[4/5] Verifying Mosquitto WebSocket listener on host port $mqttWsPort (for Cloudflare Tunnel)..." -ForegroundColor Yellow
$tcp = New-Object System.Net.Sockets.TcpClient
try {
    $tcp.ReceiveTimeout = 3000
    $tcp.SendTimeout = 3000
    $tcp.Connect("127.0.0.1", $mqttWsPort)
    $stream = $tcp.GetStream()
    $req = "GET / HTTP/1.1`r`nHost: 127.0.0.1:$mqttWsPort`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`nSec-WebSocket-Version: 13`r`nSec-WebSocket-Protocol: mqtt`r`n`r`n"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($req)
    $stream.Write($bytes, 0, $bytes.Length)
    $buf = New-Object byte[] 1024
    $read = $stream.Read($buf, 0, $buf.Length)
    $resp = [System.Text.Encoding]::ASCII.GetString($buf, 0, $read)
    if ($resp -match "HTTP/1\.1 101") {
        Write-Host "[+] PASS: WebSocket upgrade returned HTTP 101 Switching Protocols on port $mqttWsPort." -ForegroundColor Green
    } else {
        Write-Host "[-] FAIL: Unexpected response from WebSocket port ${mqttWsPort}: $resp" -ForegroundColor Red
        exit 1
    }
} finally {
    $tcp.Close()
}

Write-Host "[5/5] Verifying Cedalo Management Center Web UI on http://localhost:$mmcPort..." -ForegroundColor Yellow
$uiResp = Invoke-WebRequest -Uri "http://127.0.0.1:${mmcPort}/" -UseBasicParsing -TimeoutSec 5
if ($uiResp.StatusCode -eq 200) {
    Write-Host "[+] PASS: Cedalo Management Center UI returned HTTP 200 on port $mmcPort." -ForegroundColor Green
} else {
    Write-Host "[-] FAIL: Cedalo UI returned HTTP $($uiResp.StatusCode)." -ForegroundColor Red
    exit 1
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "[+] All MQ verification checks passed!" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Cyan
