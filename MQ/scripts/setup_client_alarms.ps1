# =============================================================================
#  setup_client_alarms.ps1 — Provision 'role-alarms-read' & 'client_alarms'
# =============================================================================
#  Creates / updates:
#    1. Role   : role-alarms-read (subscribePattern 'cde/alarms/#' -> allow)
#    2. Client : client_alarms (password: alarmpass123)
#    3. Assigns role-alarms-read to client_alarms
#    4. Verifies client & role configuration via mosquitto_ctrl
# =============================================================================

param(
    [string]$ClientUser     = "client_alarms",
    [string]$ClientPassword = "alarmpass123",
    [string]$RoleName       = "role-alarms-read",
    [string]$TopicPattern   = "cde/alarms/#"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mqDir = Split-Path -Parent $scriptDir
$envFile = Join-Path $mqDir ".env"
if (-not (Test-Path $envFile)) {
    $envFile = Join-Path $mqDir ".env.example"
}

$envVars = @{}
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $idx = $line.IndexOf("=")
            $key = $line.Substring(0, $idx).Trim()
            $val = $line.Substring($idx + 1).Trim().Trim('"').Trim("'")
            $envVars[$key] = $val
        }
    }
}

$adminUser = if ($envVars.ContainsKey("MQTT_ADMIN_USER") -and $envVars["MQTT_ADMIN_USER"]) { $envVars["MQTT_ADMIN_USER"] } else { "cedalo" }
$adminPass = if ($envVars.ContainsKey("MQTT_ADMIN_PASSWORD") -and $envVars["MQTT_ADMIN_PASSWORD"]) { $envVars["MQTT_ADMIN_PASSWORD"] } else { "cdepassword123" }

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Provisioning Mosquitto Test Subscriber & Role                  " -ForegroundColor Cyan
Write-Host "    Client User : $ClientUser                                    " -ForegroundColor Gray
Write-Host "    Password    : $ClientPassword                                " -ForegroundColor Gray
Write-Host "    Role        : $RoleName                                      " -ForegroundColor Gray
Write-Host "    Topic ACL   : subscribePattern '$TopicPattern' (allow)       " -ForegroundColor Gray
Write-Host "=================================================================" -ForegroundColor Cyan

$ErrorActionPreference = "Continue"

Write-Host "`n[1/4] Creating role '$RoleName' and adding subscribePattern ACL for '$TopicPattern'..." -ForegroundColor Yellow
docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 -u $adminUser -P $adminPass dynsec createRole $RoleName 2>$null
docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 -u $adminUser -P $adminPass dynsec addRoleACL $RoleName subscribePattern $TopicPattern allow 2>$null

Write-Host "[2/4] Creating client '$ClientUser' with password '$ClientPassword'..." -ForegroundColor Yellow
docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 -u $adminUser -P $adminPass dynsec createClient $ClientUser -p $ClientPassword 2>$null
docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 -u $adminUser -P $adminPass dynsec setClientPassword $ClientUser $ClientPassword 2>$null

Write-Host "[3/4] Assigning role '$RoleName' to client '$ClientUser'..." -ForegroundColor Yellow
docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 -u $adminUser -P $adminPass dynsec addClientRole $ClientUser $RoleName 2>$null

Write-Host "[4/4] Verifying client and role in Mosquitto Dynamic Security:" -ForegroundColor Green
Write-Host "`n--- Role Details ($RoleName) ---" -ForegroundColor Cyan
docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 -u $adminUser -P $adminPass dynsec getRole $RoleName

Write-Host "`n--- Client Details ($ClientUser) ---" -ForegroundColor Cyan
docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 -u $adminUser -P $adminPass dynsec getClient $ClientUser

Write-Host "`n[+] Done! '$ClientUser' (password: '$ClientPassword') is ready to subscribe to '$TopicPattern'." -ForegroundColor Green
