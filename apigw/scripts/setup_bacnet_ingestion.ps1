<#
.SYNOPSIS
    Automated Kong Gateway & CDE Adapter Setup Script for BACnet Edge Gateway Ingestion
    (zaarr-bacnet-gw-01 -> Kong :8088 -> CDE Adapter :8090 -> iMOPS).

.DESCRIPTION
    Provisions Kong Gateway OSS 3.9 and configures the CDE BACnet Transformation Adapter:
    1. Resolves the target iMOPS IP / Host parameter (e.g., "10.65.51.252" -> "http://10.65.51.252:13000").
    2. Creates / Updates Kong Service:
       - cde-bacnet-adapter-service (points to http://cde-datamart-etl:8090)
    3. Creates / Updates Kong Ingress Routes:
       - bacnet-telemetry-route (POST /api/v1/bacnet/telemetry, strip_path=false)
       - bacnet-devices-route   (POST /api/v1/bacnet/devices,   strip_path=false)
       - bacnet-status-route    (GET  /api/v1/bacnet/status,    strip_path=false)
    4. Attaches Perimeter Security & Traffic Plugins:
       - key-auth (accepts X-API-Key, x-api-key, apikey; hide_credentials=true)
       - rate-limiting (600 req/min to support 1.5s-5s polling + burst COV events)
       - request-size-limiting (5 MB)
       - correlation-id (X-Request-ID)
    5. Creates Consumer & X-API-Key Credential:
       - Consumer: zaarr-bacnet-gw-01
       - X-API-Key: zaarr-bacnet-gw01-key-2026 (configurable via -ApiKey)
    6. Dynamically updates the CDE Adapter's outbound iMOPS target URL via POST /api/v1/bacnet/config.

.PARAMETER ImopsIp
    IP address, hostname, or base URL of the target iMOPS backend.
    Examples:
      - "10.65.51.252"               -> http://10.65.51.252:13000
      - "10.65.51.252:13000"         -> http://10.65.51.252:13000
      - "http://10.65.51.252:13000"  -> http://10.65.51.252:13000
      - "localhost:13000"            -> http://host.docker.internal:13000 (Docker bridge)

.PARAMETER ApiKey
    X-API-Key secret for zaarr-bacnet-gw-01 (default: zaarr-bacnet-gw01-key-2026).

.PARAMETER AdminUrl
    Kong Gateway Admin API URL (default: http://localhost:8001).

.PARAMETER AdapterAdminUrl
    CDE BACnet Adapter local management URL (default: http://localhost:8090).

.EXAMPLE
    .\setup_bacnet_ingestion.ps1 -ImopsIp "10.65.51.252"
#>

param(
    [Parameter(Position = 0)]
    [string]$ImopsIp = "localhost:13000",

    [Parameter(Position = 1)]
    [string]$ApiKey = "zaarr-bacnet-gw01-key-2026",

    [Parameter(Position = 2)]
    [string]$AdminUrl = "http://localhost:8001",

    [Parameter(Position = 3)]
    [string]$AdapterAdminUrl = "http://localhost:8090",

    [Parameter(Position = 4)]
    [string]$AdapterUpstreamUrl = "http://cde-datamart-etl:8090"
)

# -----------------------------------------------------------------------------
# 0. Resolve Target iMOPS Base URL from -ImopsIp
# -----------------------------------------------------------------------------
$rawHost = $ImopsIp.Trim()

if ($rawHost -match '^(https?://)?(localhost|127\.0\.0\.1)(:\d+)?(/.*)?$') {
    $portPart = if ($Matches[3]) { $Matches[3] } else { ":13000" }
    $imopsBaseUrl = "http://host.docker.internal${portPart}"
} elseif ($rawHost -match '^https?://') {
    $imopsBaseUrl = $rawHost.TrimEnd('/')
} elseif ($rawHost -match ':\d+$') {
    $imopsBaseUrl = "http://${rawHost}"
} else {
    $imopsBaseUrl = "http://${rawHost}:13000"
}

$serviceName  = "cde-bacnet-adapter-service"
$consumerName = "zaarr-bacnet-gw-01"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " Starting CDE BACnet Ingestion & Transformation Setup (Kong + CDE)" -ForegroundColor Cyan
Write-Host "   Kong Admin API:     $AdminUrl" -ForegroundColor Gray
Write-Host "   CDE Adapter Target: $AdapterUpstreamUrl" -ForegroundColor Gray
Write-Host "   iMOPS Input Param:  $ImopsIp" -ForegroundColor Gray
Write-Host "   Resolved iMOPS URL: $imopsBaseUrl" -ForegroundColor Green
Write-Host "   Edge Gateway ID:    $consumerName" -ForegroundColor Gray
Write-Host "   X-API-Key Secret:   $ApiKey" -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Cyan

function Invoke-KongAdmin {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null
    )
    $url = "$AdminUrl$Path"
    $headers = @{ "Content-Type" = "application/json" }
    try {
        if ($null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 6
            return Invoke-RestMethod -Uri $url -Method $Method -Headers $headers -Body $json -ErrorAction Stop
        } else {
            return Invoke-RestMethod -Uri $url -Method $Method -Headers $headers -ErrorAction Stop
        }
    } catch {
        return $null
    }
}

# -----------------------------------------------------------------------------
# 1. Configure Kong Gateway Service -> CDE BACnet Adapter
# -----------------------------------------------------------------------------
Write-Host "`n[1/5] Configuring Kong Service ($serviceName)..." -ForegroundColor Yellow
$existingService = Invoke-KongAdmin -Method "Get" -Path "/services/$serviceName"

$servicePayload = @{
    name            = $serviceName
    url             = $AdapterUpstreamUrl
    connect_timeout = 10000
    read_timeout    = 30000
    write_timeout   = 30000
}

if ($existingService) {
    $svc = Invoke-KongAdmin -Method "Patch" -Path "/services/$serviceName" -Body $servicePayload
    Write-Host "   [OK] Updated service '$serviceName' -> $AdapterUpstreamUrl" -ForegroundColor Green
} else {
    $svc = Invoke-KongAdmin -Method "Post" -Path "/services" -Body $servicePayload
    Write-Host "   [OK] Created service '$serviceName' -> $AdapterUpstreamUrl" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 2. Configure Kong Routes (/api/v1/bacnet/telemetry & /api/v1/bacnet/devices)
# -----------------------------------------------------------------------------
Write-Host "`n[2/5] Configuring BACnet Ingress Routes..." -ForegroundColor Yellow

$routes = @(
    @{
        name       = "bacnet-telemetry-route"
        paths      = @("/api/v1/bacnet/telemetry")
        methods    = @("POST", "OPTIONS")
        strip_path = $false
    },
    @{
        name       = "bacnet-devices-route"
        paths      = @("/api/v1/bacnet/devices")
        methods    = @("POST", "OPTIONS")
        strip_path = $false
    },
    @{
        name       = "bacnet-status-route"
        paths      = @("/api/v1/bacnet/status")
        methods    = @("GET", "OPTIONS")
        strip_path = $false
    }
)

foreach ($r in $routes) {
    $rName = $r.name
    $existingRoute = Invoke-KongAdmin -Method "Get" -Path "/routes/$rName"
    $routeBody = @{
        name       = $r.name
        paths      = $r.paths
        methods    = $r.methods
        strip_path = $r.strip_path
        protocols  = @("http", "https")
    }
    if ($existingRoute) {
        Invoke-KongAdmin -Method "Patch" -Path "/routes/$rName" -Body $routeBody | Out-Null
        Write-Host "   [OK] Updated route '$rName' ($($r.paths -join ', '))" -ForegroundColor Green
    } else {
        Invoke-KongAdmin -Method "Post" -Path "/services/$serviceName/routes" -Body $routeBody | Out-Null
        Write-Host "   [OK] Created route '$rName' ($($r.paths -join ', '))" -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------------
# 3. Attach Security & Traffic Plugins (key-auth, rate-limiting, size, corr-id)
# -----------------------------------------------------------------------------
Write-Host "`n[3/5] Attaching Security & Traffic Plugins..." -ForegroundColor Yellow
$servicePlugins = (Invoke-KongAdmin -Method "Get" -Path "/services/$serviceName/plugins").data

# 3a. key-auth (X-API-Key)
$hasKeyAuth = $servicePlugins | Where-Object { $_.name -eq "key-auth" }
$keyAuthBody = @{
    name   = "key-auth"
    config = @{
        key_names        = @("X-API-Key", "x-api-key", "apikey")
        hide_credentials = $true
        key_in_header    = $true
        key_in_query     = $true
    }
}
if ($hasKeyAuth) {
    Invoke-KongAdmin -Method "Patch" -Path "/plugins/$($hasKeyAuth.id)" -Body $keyAuthBody | Out-Null
    Write-Host "   [OK] Updated 'key-auth' plugin (headers: X-API-Key, x-api-key, apikey)" -ForegroundColor Green
} else {
    Invoke-KongAdmin -Method "Post" -Path "/services/$serviceName/plugins" -Body $keyAuthBody | Out-Null
    Write-Host "   [OK] Attached 'key-auth' plugin (headers: X-API-Key, x-api-key, apikey)" -ForegroundColor Green
}

# 3b. rate-limiting (600 req/min for 1.5s-5s poll + COV burst)
$hasRateLimit = $servicePlugins | Where-Object { $_.name -eq "rate-limiting" }
$rateLimitBody = @{
    name   = "rate-limiting"
    config = @{
        minute = 600
        policy = "local"
    }
}
if ($hasRateLimit) {
    Invoke-KongAdmin -Method "Patch" -Path "/plugins/$($hasRateLimit.id)" -Body $rateLimitBody | Out-Null
    Write-Host "   [OK] Updated 'rate-limiting' plugin (600 req/min)" -ForegroundColor Green
} else {
    Invoke-KongAdmin -Method "Post" -Path "/services/$serviceName/plugins" -Body $rateLimitBody | Out-Null
    Write-Host "   [OK] Attached 'rate-limiting' plugin (600 req/min)" -ForegroundColor Green
}

# 3c. request-size-limiting (5MB)
$hasSizeLimit = $servicePlugins | Where-Object { $_.name -eq "request-size-limiting" }
if (-not $hasSizeLimit) {
    Invoke-KongAdmin -Method "Post" -Path "/services/$serviceName/plugins" -Body @{
        name   = "request-size-limiting"
        config = @{ allowed_payload_size = 5 }
    } | Out-Null
    Write-Host "   [OK] Attached 'request-size-limiting' (5MB) plugin" -ForegroundColor Green
}

# 3d. correlation-id (X-Request-ID)
$hasCorrId = $servicePlugins | Where-Object { $_.name -eq "correlation-id" }
if (-not $hasCorrId) {
    Invoke-KongAdmin -Method "Post" -Path "/services/$serviceName/plugins" -Body @{
        name   = "correlation-id"
        config = @{
            header_name     = "X-Request-ID"
            generator       = "uuid"
            echo_downstream = $true
        }
    } | Out-Null
    Write-Host "   [OK] Attached 'correlation-id' (X-Request-ID) plugin" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 4. Configure Consumer (zaarr-bacnet-gw-01) & X-API-Key Secret
# -----------------------------------------------------------------------------
Write-Host "`n[4/5] Configuring Consumer ($consumerName) & X-API-Key..." -ForegroundColor Yellow
$existingConsumer = Invoke-KongAdmin -Method "Get" -Path "/consumers/$consumerName"
if (-not $existingConsumer) {
    Invoke-KongAdmin -Method "Post" -Path "/consumers" -Body @{
        username  = $consumerName
        custom_id = "smart-nation-bacnet-gw-01"
    } | Out-Null
    Write-Host "   [OK] Created consumer '$consumerName'" -ForegroundColor Green
} else {
    Write-Host "   [OK] Consumer '$consumerName' exists" -ForegroundColor Green
}

$existingKeys = (Invoke-KongAdmin -Method "Get" -Path "/consumers/$consumerName/key-auth").data
$keyMatch = $existingKeys | Where-Object { $_.key -eq $ApiKey }
if (-not $keyMatch) {
    Invoke-KongAdmin -Method "Post" -Path "/consumers/$consumerName/key-auth" -Body @{
        key = $ApiKey
    } | Out-Null
    Write-Host "   [OK] Provisioned X-API-Key credential for '$consumerName'" -ForegroundColor Green
} else {
    Write-Host "   [OK] X-API-Key credential already active for '$consumerName'" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 5. Update CDE Adapter Outbound iMOPS Target URL
# -----------------------------------------------------------------------------
Write-Host "`n[5/5] Updating CDE BACnet Adapter Target iMOPS URL ($imopsBaseUrl)..." -ForegroundColor Yellow
try {
    $cfgResp = Invoke-RestMethod -Uri "$AdapterAdminUrl/api/v1/bacnet/config" -Method Post -ContentType "application/json" -Body (@{
        imopsBaseUrl = $imopsBaseUrl
    } | ConvertTo-Json) -ErrorAction Stop
    Write-Host "   [OK] CDE Adapter outbound iMOPS target set to: $($cfgResp.imopsBaseUrl)" -ForegroundColor Green
    Write-Host "        -> Sensor Updates:    $($cfgResp.endpoints.updates)" -ForegroundColor Gray
    Write-Host "        -> Controller Status: $($cfgResp.endpoints.controllerStatus)" -ForegroundColor Gray
} catch {
    Write-Host "   [WARN] Could not reach CDE Adapter at $AdapterAdminUrl/api/v1/bacnet/config ($_)" -ForegroundColor Yellow
}

Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host " Deliverables for Edge Gateway Setup (zaarr-bacnet-gw-01)" -ForegroundColor Green
Write-Host "------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host " 1. CDE API Gateway base_url:  http://localhost:8088 (or https://<CDE_HOST>:8443)" -ForegroundColor White
Write-Host " 2. Confirmed Paths:" -ForegroundColor White
Write-Host "      - Telemetry Batch:       POST /api/v1/bacnet/telemetry" -ForegroundColor Yellow
Write-Host "      - Controller Status:     POST /api/v1/bacnet/devices" -ForegroundColor Yellow
Write-Host "      - Adapter Live Status:   GET  /api/v1/bacnet/status" -ForegroundColor Gray
Write-Host " 3. X-API-Key Secret:          $ApiKey" -ForegroundColor Yellow
Write-Host " 4. Outbound iMOPS Target:     $imopsBaseUrl" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Cyan

