<#
.SYNOPSIS
    Automated Kong Gateway Setup Script for Digital Twin API & Real-time Provider.
.DESCRIPTION
    Provisions Kong Gateway OSS 3.9 to serve as the secure API Provider for external
    Digital Twins (e.g., Vizzio, Taylor, Proscalar).
    
    Creates:
    - Gateway Service: imops-twin-rest-service (Reconcil REST APIs: /api/visualization, /api/auth)
    - Gateway Service: imops-twin-realtime-service (WebSocket / Streaming: /ws, /socket.io) with 5-minute keepalive
    - Routes:
      1. twin-visualization-route   (/api/visualization)
      2. twin-auth-route            (/api/auth)
      3. twin-ws-route              (/ws)
      4. twin-socketio-route        (/socket.io)
    - Plugins:
      - CORS (permissive for 3D/WebGL browser origins)
      - Rate Limiting (120 req/min burst protection)
      - Basic Auth (hide_credentials=false, verifies credentials and passes to upstream)
    - Consumer: vizzio-twin-consumer (Basic Auth: vizzio@imops.local / xAJHkkm7m3V5MhtF0xGM)

.PARAMETER UpstreamHost
    Host, IP, or base URL of the target iMOPS backend.
    Examples:
      - "10.65.51.252"                 -> resolves to http://10.65.51.252:13000
      - "10.65.51.252:13000"           -> resolves to http://10.65.51.252:13000
      - "http://10.65.51.252:13000"    -> resolves to http://10.65.51.252:13000
      - "host.docker.internal:13000"   -> resolves to http://host.docker.internal:13000 (Local Docker)
.PARAMETER AdminUrl
    Kong Gateway Admin API URL (default: http://localhost:8001).
.PARAMETER ApiKey
    API Key for the Digital Twin consumer (default: vizzio-digital-twin-key-2026).
#>

param(
    [Parameter(Position = 0)]
    [string]$UpstreamHost = "localhost:13000",

    [Parameter(Position = 1)]
    [string]$AdminUrl = "http://localhost:8001",

    [Parameter(Position = 2)]
    [string]$ApiKey = "vizzio-digital-twin-key-2026",

    [Parameter(Position = 3)]
    [bool]$InjectAuth = $true,

    [Parameter(Position = 4)]
    [string]$AuthEmail = "vizzio@imops.local",

    [Parameter(Position = 5)]
    [string]$AuthPassword = "xAJHkkm7m3V5MhtF0xGM"
)

# -----------------------------------------------------------------------------
# Upstream URL Resolution
# -----------------------------------------------------------------------------
$rawHost = $UpstreamHost.Trim()

# When Kong runs inside Docker, 'localhost' refers to the container itself.
# Map localhost / 127.0.0.1 to host.docker.internal so Kong can reach the host backend.
if ($rawHost -match '^(https?://)?(localhost|127\.0\.0\.1)(:\d+)?(/.*)?$') {
    $portPart = if ($Matches[3]) { $Matches[3] } else { ":13000" }
    $baseUrl = "http://host.docker.internal${portPart}"
} elseif ($rawHost -match '^https?://') {
    $baseUrl = $rawHost.TrimEnd('/')
} elseif ($rawHost -match ':\d+$') {
    $baseUrl = "http://${rawHost}"
} else {
    $baseUrl = "http://${rawHost}:13000"
}

$restServiceUrl = "$baseUrl"
$realtimeServiceUrl = "$baseUrl"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Starting Kong Gateway: Digital Twin Provider Provisioning" -ForegroundColor Cyan
Write-Host "   Admin API:     $AdminUrl" -ForegroundColor Gray
Write-Host "   Target Host:   $UpstreamHost (default)" -ForegroundColor Gray
Write-Host "   Resolved Base: $baseUrl" -ForegroundColor Green
Write-Host "   Consumer Key:  $ApiKey" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan

# Helper to execute REST requests against Kong Admin API
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
            $json = $Body | ConvertTo-Json -Depth 5
            return Invoke-RestMethod -Uri $url -Method $Method -Headers $headers -Body $json -ErrorAction Stop
        } else {
            return Invoke-RestMethod -Uri $url -Method $Method -Headers $headers -ErrorAction Stop
        }
    } catch {
        $stream = $_.Exception.Response.GetResponseStream()
        if ($stream) {
            $reader = New-Object System.IO.StreamReader($stream)
            $respBody = $reader.ReadToEnd()
            Write-Host "   [WARN] Kong Admin API ($url): $respBody" -ForegroundColor Red
        } else {
            Write-Host "   [WARN] Kong Admin API ($url): $_" -ForegroundColor Red
        }
        return $null
    }
}

# -----------------------------------------------------------------------------
# 1. Gateway Service: REST APIs (Reconciliation)
# -----------------------------------------------------------------------------
$restServiceName = "imops-twin-rest-service"
Write-Host ""
Write-Host "[1/5] Configuring REST Service ($restServiceName)..." -ForegroundColor Yellow

$existingRest = Invoke-KongAdmin -Method "Get" -Path "/services/$restServiceName"
if ($existingRest) {
    Write-Host "   Updating existing service $restServiceName..." -ForegroundColor Gray
    $restService = Invoke-KongAdmin -Method "Patch" -Path "/services/$restServiceName" -Body @{
        url = $restServiceUrl
        connect_timeout = 60000
        read_timeout    = 60000
        write_timeout   = 60000
    }
} else {
    Write-Host "   Creating new service $restServiceName..." -ForegroundColor Gray
    $restService = Invoke-KongAdmin -Method "Post" -Path "/services" -Body @{
        name = $restServiceName
        url  = $restServiceUrl
        connect_timeout = 60000
        read_timeout    = 60000
        write_timeout   = 60000
    }
}

if ($restService) {
    Write-Host "   [OK] REST Service ready (ID: $($restService.id)) -> $restServiceUrl" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 2. Gateway Service: Real-Time Stream (WebSocket / Socket.io)
# -----------------------------------------------------------------------------
$wsServiceName = "imops-twin-realtime-service"
Write-Host ""
Write-Host "[2/5] Configuring Real-Time Stream Service ($wsServiceName)..." -ForegroundColor Yellow

$existingWs = Invoke-KongAdmin -Method "Get" -Path "/services/$wsServiceName"
if ($existingWs) {
    Write-Host "   Updating existing service $wsServiceName..." -ForegroundColor Gray
    $wsService = Invoke-KongAdmin -Method "Patch" -Path "/services/$wsServiceName" -Body @{
        url = $realtimeServiceUrl
        connect_timeout = 60000
        read_timeout    = 300000
        write_timeout   = 300000
    }
} else {
    Write-Host "   Creating new service $wsServiceName..." -ForegroundColor Gray
    $wsService = Invoke-KongAdmin -Method "Post" -Path "/services" -Body @{
        name = $wsServiceName
        url  = $realtimeServiceUrl
        connect_timeout = 60000
        read_timeout    = 300000
        write_timeout   = 300000
    }
}

if ($wsService) {
    Write-Host "   [OK] Real-time Service ready (ID: $($wsService.id)) -> $realtimeServiceUrl (Timeout: 300s)" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 3. Create / Verify Routes
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "[3/5] Configuring Routes..." -ForegroundColor Yellow

$routesToConfig = @(
    @{
        name        = "twin-visualization-route"
        serviceName = $restServiceName
        paths       = @("/api/visualization")
        strip_path  = $false
        protocols   = @("http", "https")
    },
    @{
        name        = "twin-auth-route"
        serviceName = $restServiceName
        paths       = @("/api/auth")
        strip_path  = $false
        protocols   = @("http", "https")
    },
    @{
        name        = "twin-ws-route"
        serviceName = $wsServiceName
        paths       = @("/ws")
        strip_path  = $false
        protocols   = @("http", "https")
    },
    @{
        name        = "twin-socketio-route"
        serviceName = $wsServiceName
        paths       = @("/socket.io")
        strip_path  = $false
        protocols   = @("http", "https")
    }
)

foreach ($r in $routesToConfig) {
    $routeName = $r.name
    $sName = $r.serviceName
    $existingRoute = Invoke-KongAdmin -Method "Get" -Path "/routes/$routeName"
    
    $routeBody = @{
        name       = $r.name
        paths      = $r.paths
        strip_path = $r.strip_path
        protocols  = $r.protocols
    }

    if ($existingRoute) {
        $updated = Invoke-KongAdmin -Method "Patch" -Path "/routes/$routeName" -Body $routeBody
        Write-Host "   [OK] Route '$routeName' updated ($($r.paths -join ', '))" -ForegroundColor Green
    } else {
        $created = Invoke-KongAdmin -Method "Post" -Path "/services/$sName/routes" -Body $routeBody
        Write-Host "   [OK] Route '$routeName' created on $sName ($($r.paths -join ', '))" -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------------
# 4. Attach Security & Traffic Plugins
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "[4/5] Configuring Plugins (CORS, Rate Limiting)..." -ForegroundColor Yellow

# Attach CORS to REST Service
$restPlugins = (Invoke-KongAdmin -Method "Get" -Path "/services/$restServiceName/plugins").data
$hasCors = $restPlugins | Where-Object { $_.name -eq "cors" }
if (-not $hasCors) {
    Invoke-KongAdmin -Method "Post" -Path "/services/$restServiceName/plugins" -Body @{
        name   = "cors"
        config = @{
            origins          = @("*")
            methods          = @("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
            headers          = @("Accept", "Authorization", "Content-Type", "apikey", "x-api-key", "Origin", "X-Requested-With")
            credentials      = $true
            max_age          = 3600
        }
    } | Out-Null
    Write-Host "   [OK] Attached 'cors' plugin to $restServiceName" -ForegroundColor Green
} else {
    Write-Host "   [INFO] 'cors' plugin already active on $restServiceName" -ForegroundColor Gray
}

# Attach CORS to Real-time Service
$wsPlugins = (Invoke-KongAdmin -Method "Get" -Path "/services/$wsServiceName/plugins").data
$hasWsCors = $wsPlugins | Where-Object { $_.name -eq "cors" }
if (-not $hasWsCors) {
    Invoke-KongAdmin -Method "Post" -Path "/services/$wsServiceName/plugins" -Body @{
        name   = "cors"
        config = @{
            origins          = @("*")
            methods          = @("GET", "POST", "OPTIONS")
            headers          = @("Accept", "Authorization", "Content-Type", "apikey", "x-api-key", "Sec-WebSocket-Key", "Sec-WebSocket-Version", "Sec-WebSocket-Extensions")
            credentials      = $true
            max_age          = 3600
        }
    } | Out-Null
    Write-Host "   [OK] Attached 'cors' plugin to $wsServiceName" -ForegroundColor Green
} else {
    Write-Host "   [INFO] 'cors' plugin already active on $wsServiceName" -ForegroundColor Gray
}

# Attach Rate Limiting to REST Service (120 req/min protection)
$hasRateLimit = $restPlugins | Where-Object { $_.name -eq "rate-limiting" }
if (-not $hasRateLimit) {
    Invoke-KongAdmin -Method "Post" -Path "/services/$restServiceName/plugins" -Body @{
        name   = "rate-limiting"
        config = @{
            minute = 120
            policy = "local"
        }
    } | Out-Null
    Write-Host "   [OK] Attached 'rate-limiting' (120 req/min) to $restServiceName" -ForegroundColor Green
} else {
    Write-Host "   [INFO] 'rate-limiting' plugin already active on $restServiceName" -ForegroundColor Gray
}

# Attach Basic Auth to twin-visualization-route (Perimeter validation + pass-through to upstream)
$routePlugins = (Invoke-KongAdmin -Method "Get" -Path "/routes/twin-visualization-route/plugins").data
$hasBasicAuth = $routePlugins | Where-Object { $_.name -eq "basic-auth" }
if (-not $hasBasicAuth) {
    Invoke-KongAdmin -Method "Post" -Path "/routes/twin-visualization-route/plugins" -Body @{
        name   = "basic-auth"
        config = @{
            hide_credentials = $false
        }
    } | Out-Null
    Write-Host "   [OK] Attached 'basic-auth' (hide_credentials=false) to twin-visualization-route" -ForegroundColor Green
} else {
    Write-Host "   [INFO] 'basic-auth' plugin already active on twin-visualization-route" -ForegroundColor Gray
}

# Clean up legacy request-transformer if present
$hasTransformer = $routePlugins | Where-Object { $_.name -eq "request-transformer" }
if ($hasTransformer) {
    Invoke-KongAdmin -Method "Delete" -Path "/plugins/$($hasTransformer.id)" | Out-Null
    Write-Host "   [OK] Removed legacy 'request-transformer' plugin" -ForegroundColor Gray
}

# -----------------------------------------------------------------------------
# 5. Consumer & Basic Auth Credentials
# -----------------------------------------------------------------------------
$consumerName = "vizzio-twin-consumer"
Write-Host ""
Write-Host "[5/5] Configuring Consumer ($consumerName) & Credentials..." -ForegroundColor Yellow

$existingConsumer = Invoke-KongAdmin -Method "Get" -Path "/consumers/$consumerName"
if (-not $existingConsumer) {
    $existingConsumer = Invoke-KongAdmin -Method "Post" -Path "/consumers" -Body @{
        username  = $consumerName
        custom_id = "twin-vizzio-tenant"
    }
    Write-Host "   [OK] Consumer '$consumerName' created." -ForegroundColor Green
} else {
    Write-Host "   [INFO] Consumer '$consumerName' exists (ID: $($existingConsumer.id))." -ForegroundColor Gray
}

# Ensure Basic Auth credentials exist for consumer
$allBasicAuth = (Invoke-KongAdmin -Method "Get" -Path "/basic-auths").data
$credExists = $allBasicAuth | Where-Object { $_.username -eq $AuthEmail }
if (-not $credExists -and $existingConsumer) {
    Invoke-KongAdmin -Method "Post" -Path "/consumers/$consumerName/basic-auth" -Body @{
        username = $AuthEmail
        password = $AuthPassword
    } | Out-Null
    Write-Host "   [OK] Provisioned Basic Auth credentials for '$AuthEmail'" -ForegroundColor Green
} else {
    Write-Host "   [INFO] Basic Auth credentials for '$AuthEmail' already configured in Kong." -ForegroundColor Gray
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Kong Gateway Setup Complete for Digital Twins!" -ForegroundColor Green
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host " Public Ingress Endpoints (Port 8088):" -ForegroundColor White
Write-Host "   REST Reconcil:  http://localhost:8088/api/visualization/hierarchy" -ForegroundColor Yellow
Write-Host "   REST Incidents: http://localhost:8088/api/visualization/incidents" -ForegroundColor Yellow
Write-Host "   REST Login:     http://localhost:8088/api/auth/login" -ForegroundColor Yellow
Write-Host "   WebSocket:      ws://localhost:8088/ws" -ForegroundColor Yellow
Write-Host "   Socket.IO:      http://localhost:8088/socket.io/" -ForegroundColor Yellow
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host " Authentication: HTTP Basic Auth (Pass-Through to Upstream)" -ForegroundColor White
Write-Host "   Username:     $AuthEmail" -ForegroundColor Yellow
Write-Host "   Password:     $AuthPassword" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan
