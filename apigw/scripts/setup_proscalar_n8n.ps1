<#
.SYNOPSIS
    Automated Kong Gateway Setup Script for Proscalar Webhook Ingestion via n8n (Option C).
.DESCRIPTION
    Creates / Updates:
    - Gateway Service: imops-proscalar-n8n-service (points to http://n8n-server:5678/webhook/proscalar)
    - Route: proscalar-webhook-route (POST /api/proscalar/webhook)
    - Edge Plugins:
        * basic-auth (hide_credentials: true)
        * rate-limiting (120 req/min)
        * request-size-limiting (5MB)
        * correlation-id (X-Request-ID)
        * request-transformer (attaches X-Source header)
    - Consumer: proscalar_webhook_client (proscalar@gmail.com / secure pass)
#>

param(
    [Parameter(Position = 0)]
    [string]$N8nUpstreamUrl = "http://n8n-server:5678/webhook/proscalar",

    [Parameter(Position = 1)]
    [string]$ProscalarUsername = "proscalar@gmail.com",

    [Parameter(Position = 2)]
    [string]$ProscalarPassword = "fwpkyjcf2i8fcoP05yEz"
)

$adminUrl = "http://localhost:8001"
$serviceName = "imops-proscalar-n8n-service"
$routeName = "proscalar-webhook-route"
$consumerName = "proscalar_webhook_client"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "🚀 Starting Proscalar -> n8n Kong Ingress Setup (Option C)" -ForegroundColor Cyan
Write-Host "   Admin URL:       $adminUrl" -ForegroundColor Gray
Write-Host "   n8n Upstream:    $N8nUpstreamUrl" -ForegroundColor Gray
Write-Host "   Consumer:        $consumerName ($ProscalarUsername)" -ForegroundColor Gray
Write-Host "====================================================" -ForegroundColor Cyan

# 1. Create or Update Gateway Service
Write-Host "`n[1/5] Configuring Gateway Service: $serviceName..." -ForegroundColor Yellow
try {
    $existingService = Invoke-RestMethod -Uri "$adminUrl/services/$serviceName" -Method Get -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Host "Service $serviceName already exists (ID: $($existingService.id)). Ensuring upstream URL..." -ForegroundColor Green
        Invoke-RestMethod -Uri "$adminUrl/services/$serviceName" -Method Patch -ContentType "application/json" -Body (@{ url = $N8nUpstreamUrl } | ConvertTo-Json) | Out-Null
        $serviceId = $existingService.id
    }
} catch {
    $serviceJson = @{
        name = $serviceName
        url = $N8nUpstreamUrl
    } | ConvertTo-Json
    $serviceResp = Invoke-RestMethod -Uri "$adminUrl/services" -Method Post -ContentType "application/json" -Body $serviceJson
    $serviceId = $serviceResp.id
    Write-Host "Service $serviceName created successfully (ID: $serviceId)." -ForegroundColor Green
}

# 2. Create or Update Ingress Route
Write-Host "`n[2/5] Configuring Ingress Route: $routeName..." -ForegroundColor Yellow
try {
    $existingRoute = Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/routes/$routeName" -Method Get -ErrorAction SilentlyContinue
    if ($existingRoute) {
        Write-Host "Route $routeName already exists (ID: $($existingRoute.id)). Updating..." -ForegroundColor Green
        $routeUpdate = @{
            paths = @("/api/proscalar/webhook")
            methods = @("POST")
            strip_path = $true
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$adminUrl/routes/$($existingRoute.id)" -Method Patch -ContentType "application/json" -Body $routeUpdate | Out-Null
        $routeId = $existingRoute.id
    }
} catch {
    $routeJson = @{
        name = $routeName
        paths = @("/api/proscalar/webhook")
        methods = @("POST")
        strip_path = $true
    } | ConvertTo-Json
    $routeResp = Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/routes" -Method Post -ContentType "application/json" -Body $routeJson
    $routeId = $routeResp.id
    Write-Host "Route $routeName created successfully (ID: $routeId)." -ForegroundColor Green
}

# 3. Configure Plugins on Service / Route
Write-Host "`n[3/5] Attaching Security & Policy Plugins..." -ForegroundColor Yellow
try {
    $existingPlugins = Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Get
    
    # 3a. basic-auth (strips credentials before forwarding to n8n)
    $hasBasicAuth = $existingPlugins.data | Where-Object { $_.name -eq "basic-auth" }
    if (-not $hasBasicAuth) {
        $basicAuthJson = @{
            name = "basic-auth"
            config = @{ hide_credentials = $true }
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Post -ContentType "application/json" -Body $basicAuthJson | Out-Null
        Write-Host "Attached 'basic-auth' plugin (hide_credentials = true)." -ForegroundColor Green
    } else {
        Write-Host "'basic-auth' plugin already attached." -ForegroundColor Gray
    }

    # 3b. rate-limiting (120 requests/minute)
    $hasRateLimit = $existingPlugins.data | Where-Object { $_.name -eq "rate-limiting" }
    if (-not $hasRateLimit) {
        $rateLimitJson = @{
            name = "rate-limiting"
            config = @{ minute = 120; policy = "local" }
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Post -ContentType "application/json" -Body $rateLimitJson | Out-Null
        Write-Host "Attached 'rate-limiting' (120 req/min) plugin." -ForegroundColor Green
    } else {
        Write-Host "'rate-limiting' plugin already attached." -ForegroundColor Gray
    }

    # 3c. request-size-limiting (5MB)
    $hasSizeLimit = $existingPlugins.data | Where-Object { $_.name -eq "request-size-limiting" }
    if (-not $hasSizeLimit) {
        $sizeLimitJson = @{
            name = "request-size-limiting"
            config = @{ allowed_payload_size = 5 }
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Post -ContentType "application/json" -Body $sizeLimitJson | Out-Null
        Write-Host "Attached 'request-size-limiting' (5MB) plugin." -ForegroundColor Green
    } else {
        Write-Host "'request-size-limiting' plugin already attached." -ForegroundColor Gray
    }

    # 3d. correlation-id (X-Request-ID)
    $hasCorrId = $existingPlugins.data | Where-Object { $_.name -eq "correlation-id" }
    if (-not $hasCorrId) {
        $corrIdJson = @{
            name = "correlation-id"
            config = @{
                header_name = "X-Request-ID"
                generator = "uuid"
                echo_downstream = $true
            }
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Post -ContentType "application/json" -Body $corrIdJson | Out-Null
        Write-Host "Attached 'correlation-id' plugin (header: X-Request-ID)." -ForegroundColor Green
    } else {
        Write-Host "'correlation-id' plugin already attached." -ForegroundColor Gray
    }

    # 3e. request-transformer (inject X-Source header)
    $hasTransformer = $existingPlugins.data | Where-Object { $_.name -eq "request-transformer" }
    if (-not $hasTransformer) {
        $transformerJson = '{"name":"request-transformer","config":{"add":{"headers":["X-Source:Kong-Proscalar-Gateway"]}}}'
        Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Post -ContentType "application/json" -Body $transformerJson | Out-Null
        Write-Host "Attached 'request-transformer' plugin (X-Source: Kong-Proscalar-Gateway)." -ForegroundColor Green
    } else {
        Write-Host "'request-transformer' plugin already attached." -ForegroundColor Gray
    }
} catch {
    Write-Host "Plugin configuration warning: $_" -ForegroundColor Yellow
}

# 4. Create Consumer & Credentials
Write-Host "`n[4/5] Configuring Consumer & Credentials..." -ForegroundColor Yellow
try {
    $existingConsumer = Invoke-RestMethod -Uri "$adminUrl/consumers/$consumerName" -Method Get -ErrorAction SilentlyContinue
    if ($existingConsumer) {
        Write-Host "Consumer $consumerName already exists (ID: $($existingConsumer.id))." -ForegroundColor Green
    }
} catch {
    $consumerJson = @{
        username = $consumerName
        custom_id = "vendor-proscalar-tu"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$adminUrl/consumers" -Method Post -ContentType "application/json" -Body $consumerJson | Out-Null
    Write-Host "Consumer $consumerName created successfully." -ForegroundColor Green
}

# Attach Basic Auth Credential
try {
    $creds = Invoke-RestMethod -Uri "$adminUrl/consumers/$consumerName/basic-auth" -Method Get
    foreach ($c in $creds.data) {
        if ($c.username -eq $ProscalarUsername) {
            Invoke-RestMethod -Uri "$adminUrl/consumers/$consumerName/basic-auth/$($c.id)" -Method Delete | Out-Null
            Write-Host "Removed existing basic-auth credential ($ProscalarUsername)." -ForegroundColor Gray
        }
    }
    $credJson = @{
        username = $ProscalarUsername
        password = $ProscalarPassword
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$adminUrl/consumers/$consumerName/basic-auth" -Method Post -ContentType "application/json" -Body $credJson | Out-Null
    Write-Host "Configured basic-auth credentials ($ProscalarUsername)." -ForegroundColor Green
} catch {
    Write-Host "Credential configuration notice: $_" -ForegroundColor Yellow
}

# 5. Validation Summary
Write-Host "`n[5/5] Provisioning Complete! Summary:" -ForegroundColor Yellow
Write-Host "----------------------------------------------------" -ForegroundColor Gray
Write-Host "Ingress Endpoint:  POST http://localhost:8088/api/proscalar/webhook" -ForegroundColor Cyan
Write-Host "Upstream Target:   $N8nUpstreamUrl" -ForegroundColor Cyan
Write-Host "Auth Mechanism:    HTTP Basic Auth ($ProscalarUsername)" -ForegroundColor Cyan
Write-Host "Perimeter Plugins: basic-auth, rate-limiting, request-size-limiting, correlation-id, request-transformer" -ForegroundColor Gray
Write-Host "====================================================" -ForegroundColor Cyan
