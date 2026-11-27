# =============================================================================
#  deploy_mq.ps1 — Initialize Dynamic Security and launch Mosquitto + Cedalo UI
# =============================================================================
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mqDir = Split-Path -Parent $scriptDir

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Deploying CDE Message Queue (Mosquitto + Cedalo MC)            " -ForegroundColor Cyan
Write-Host "  Directory: $mqDir                                              " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

Set-Location $mqDir

# 1. Ensure .env exists
if (-not (Test-Path ".env")) {
    Write-Host "[*] .env file not found. Copying from .env.example..." -ForegroundColor Yellow
    Copy-Item ".env.example" ".env"
}

# Load environment variables from .env
$envVars = @{}
Get-Content ".env" | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
        $idx = $line.IndexOf("=")
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim().Trim('"').Trim("'")
        $envVars[$key] = $val
    }
}

function Get-EnvOrDefault([string]$key, [string]$defaultVal) {
    if ($envVars.ContainsKey($key) -and $envVars[$key] -ne "") { return $envVars[$key] }
    return $defaultVal
}

$mqttPort              = Get-EnvOrDefault "MQTT_PORT" "1883"
$mqttWsPort            = Get-EnvOrDefault "MQTT_WS_PORT" "9002"
$mmcPort               = Get-EnvOrDefault "MMC_PORT" "8089"
$mqttAdminUser         = Get-EnvOrDefault "MQTT_ADMIN_USER" "cedalo"
$mqttAdminPassword     = Get-EnvOrDefault "MQTT_ADMIN_PASSWORD" "cdepassword123"
$mqttPublisherUser     = Get-EnvOrDefault "MQTT_PUBLISHER_USER" "cde-publisher"
$mqttPublisherPassword = Get-EnvOrDefault "MQTT_PUBLISHER_PASSWORD" "cdepublisher123"
$mmcAdminUser          = Get-EnvOrDefault "MMC_ADMIN_USER" "admin"

# 2. Check / Create external Docker network 'cde-network'
$netCheck = docker network ls --filter "name=^cde-network$" -q
if (-not $netCheck) {
    Write-Host "[+] Creating external Docker network 'cde-network'..." -ForegroundColor Yellow
    docker network create cde-network | Out-Null
} else {
    Write-Host "[+] Docker network 'cde-network' already exists." -ForegroundColor Green
}

# 3. Prepare directories
$mosquittoDataDir = Join-Path (Join-Path $mqDir "mosquitto") "data"
$mosquittoLogDir  = Join-Path (Join-Path $mqDir "mosquitto") "log"
$mmcConfigDir     = Join-Path (Join-Path $mqDir "management-center") "config"

New-Item -ItemType Directory -Force -Path $mosquittoDataDir, $mosquittoLogDir, $mmcConfigDir | Out-Null

# Initialize Cedalo config.json if absent (UTF-8 without BOM for JSON parsers)
$mmcConfigPath = Join-Path $mmcConfigDir "config.json"
if (-not (Test-Path $mmcConfigPath)) {
    Write-Host "[+] Creating initial management-center/config/config.json..." -ForegroundColor Yellow
    $defaultConfig = @"
{
  "connections": [],
  "tools": {
    "streamsheets": {
      "instances": []
    }
  },
  "plugins": []
}
"@
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($mmcConfigPath, $defaultConfig, $utf8NoBom)
}

# 4. Initialize Mosquitto Dynamic Security file on first run
$dynsecPath = Join-Path $mosquittoDataDir "dynamic-security.json"
$firstInit = $false
if (-not (Test-Path $dynsecPath)) {
    $firstInit = $true
    Write-Host "[+] Initializing Mosquitto Dynamic Security (admin user: $mqttAdminUser)..." -ForegroundColor Yellow
    docker run --rm --user root `
        -e "MQTT_ADMIN_USER=$mqttAdminUser" `
        -e "MQTT_ADMIN_PASSWORD=$mqttAdminPassword" `
        -v "${mosquittoDataDir}:/mosquitto/data" `
        -v "${mosquittoLogDir}:/mosquitto/log" `
        eclipse-mosquitto:2 sh -c 'mosquitto_ctrl dynsec init /mosquitto/data/dynamic-security.json "$MQTT_ADMIN_USER" "$MQTT_ADMIN_PASSWORD" && chown -R 1883:1883 /mosquitto/data /mosquitto/log && chmod 600 /mosquitto/data/dynamic-security.json'
    if ($LASTEXITCODE -ne 0) { throw "Failed to initialize Mosquitto Dynamic Security." }
} else {
    Write-Host "[+] Existing mosquitto/data/dynamic-security.json found; preserving current users/ACLs." -ForegroundColor Green
    docker run --rm --user root `
        -v "${mosquittoDataDir}:/mosquitto/data" `
        -v "${mosquittoLogDir}:/mosquitto/log" `
        eclipse-mosquitto:2 sh -c 'chown -R 1883:1883 /mosquitto/data /mosquitto/log'
}

# 5. Launch containers
Write-Host "[+] Starting containers via docker compose..." -ForegroundColor Yellow
docker compose up -d
if ($LASTEXITCODE -ne 0) { throw "docker compose up failed." }

# 6. Wait for Mosquitto and ensure default ACLs & cde-publisher exist (idempotent)
Write-Host "[+] Waiting for cde-mosquitto to accept connections..." -ForegroundColor Yellow
$ready = $false
for ($i = 0; $i -lt 20; $i++) {
    $ErrorActionPreference = "Continue"
    docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 -u $mqttAdminUser -P $mqttAdminPassword dynsec listRoles *> $null
    $rc = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    if ($rc -eq 0) {
        $ready = $true
        break
    }
    Start-Sleep -Seconds 1
}
if (-not $ready) { throw "Timed out waiting for cde-mosquitto." }

$ErrorActionPreference = "Continue"
$rolesOutput = docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 -u $mqttAdminUser -P $mqttAdminPassword dynsec listRoles 2>$null
$ErrorActionPreference = "Stop"
$hasPublisherRole = ($rolesOutput -split "`r?`n") -contains "cde-publisher"

if ($firstInit -or -not $hasPublisherRole) {
    Write-Host "[+] Setting default ACLs (publishClientSend=deny, subscribe=deny, publishClientReceive=allow)..." -ForegroundColor Yellow
    docker exec `
        -e "MQTT_ADMIN_USER=$mqttAdminUser" `
        -e "MQTT_ADMIN_PASSWORD=$mqttAdminPassword" `
        cde-mosquitto sh -c '
            mosquitto_ctrl -h localhost -p 1883 -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec setDefaultACLAccess publishClientSend deny
            mosquitto_ctrl -h localhost -p 1883 -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec setDefaultACLAccess publishClientReceive allow
            mosquitto_ctrl -h localhost -p 1883 -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec setDefaultACLAccess subscribe deny
            mosquitto_ctrl -h localhost -p 1883 -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec setDefaultACLAccess unsubscribe allow
        '

    Write-Host "[+] Creating internal publisher role 'cde-publisher' (publish cde/#) and client '$mqttPublisherUser'..." -ForegroundColor Yellow
    docker exec `
        -e "MQTT_ADMIN_USER=$mqttAdminUser" `
        -e "MQTT_ADMIN_PASSWORD=$mqttAdminPassword" `
        -e "MQTT_PUBLISHER_USER=$mqttPublisherUser" `
        -e "MQTT_PUBLISHER_PASSWORD=$mqttPublisherPassword" `
        cde-mosquitto sh -c '
            mosquitto_ctrl -h localhost -p 1883 -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec createRole cde-publisher || true
            mosquitto_ctrl -h localhost -p 1883 -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec addRoleACL cde-publisher publishClientSend "cde/#" allow || true
            mosquitto_ctrl -h localhost -p 1883 -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec createClient "$MQTT_PUBLISHER_USER" -p "$MQTT_PUBLISHER_PASSWORD" || true
            mosquitto_ctrl -h localhost -p 1883 -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec addClientRole "$MQTT_PUBLISHER_USER" cde-publisher || true
        '
}

Write-Host ""
Write-Host "[+] CDE Message Queue deployed successfully!" -ForegroundColor Green
Write-Host "    - Cedalo Management UI: http://localhost:${mmcPort} (user: ${mmcAdminUser})" -ForegroundColor Green
Write-Host "    - Mosquitto MQTT (TCP): mqtt://localhost:${mqttPort} (internal: mqtt://cde-mosquitto:1883)" -ForegroundColor Green
Write-Host "    - Mosquitto WebSockets: ws://localhost:${mqttWsPort} (Cloudflare Tunnel target: http://localhost:${mqttWsPort})" -ForegroundColor Green
Write-Host "    - Default Publisher:    ${mqttPublisherUser} (allowed to publish to cde/#)" -ForegroundColor Green
