<#
.SYNOPSIS
    Automated Kong Gateway Setup Script for Project DORS Video Analytics (VA) Ingress.
.DESCRIPTION
    Creates:
    - Gateway Service: imops-dors-incident-service (points to http://host.docker.internal:3000/api/incidents/monitor)
    - Service Plugins: basic-auth, rate-limiting (60 req/min)
    - Consumer: va_dors_consumer (credentials: dors_user@isems.com / 1Pu1znaPbTqXcyC5KVpP)
    - 4 Routes + pre-function dynamic translator plugins:
      1. va-dors-dop-c02-cyclist      (/va/dors-dop-c02-cyclist)
      2. va-dors-waiting-c03-cyclist  (/va/dors-waiting-c03-cyclist)
      3. va-dors-dop-c01-illegal      (/va/dors-dop-c01-illegal)
      4. va-dors-dop-c02-illegal      (/va/dors-dop-c02-illegal)
#>

$adminUrl = "http://localhost:8001"
$serviceName = "imops-dors-incident-service"
$targetUrl = "http://host.docker.internal:13000/api/incidents/monitor"
$consumerName = "va_dors_consumer"
$dorsUsername = "dors_user@isems.com"
$dorsPassword = "1Pu1znaPbTqXcyC5KVpP"
$dorsBase64Auth = "Basic ZG9yc191c2VyQGlzZW1zLmNvbToxUHUxem5hUGJUcVhjeUM1S1ZwUA=="

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "🚀 Starting DORS VA Ingress Setup on Kong Gateway" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# 1. Create or verify Gateway Service
Write-Host "`n[1/5] Configuring Gateway Service: $serviceName..." -ForegroundColor Yellow
try {
    $existingService = Invoke-RestMethod -Uri "$adminUrl/services/$serviceName" -Method Get -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Host "Service $serviceName already exists (ID: $($existingService.id))." -ForegroundColor Green
        $serviceId = $existingService.id
    }
} catch {
    $serviceJson = @{
        name = $serviceName
        url = $targetUrl
    } | ConvertTo-Json
    $serviceResp = Invoke-RestMethod -Uri "$adminUrl/services" -Method Post -ContentType "application/json" -Body $serviceJson
    $serviceId = $serviceResp.id
    Write-Host "Service $serviceName created successfully (ID: $serviceId)." -ForegroundColor Green
}

# 2. Attach basic-auth & rate-limiting plugins to Service
Write-Host "`n[2/5] Attaching Service Plugins (basic-auth, rate-limiting)..." -ForegroundColor Yellow
try {
    $existingPlugins = Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Get
    $hasBasicAuth = $existingPlugins.data | Where-Object { $_.name -eq "basic-auth" }
    if (-not $hasBasicAuth) {
        $basicAuthJson = @{
            name = "basic-auth"
            config = @{
                hide_credentials = $false
            }
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Post -ContentType "application/json" -Body $basicAuthJson | Out-Null
        Write-Host "Attached 'basic-auth' plugin." -ForegroundColor Green
    } else {
        Write-Host "'basic-auth' plugin already attached." -ForegroundColor Gray
    }

    $hasRateLimit = $existingPlugins.data | Where-Object { $_.name -eq "rate-limiting" }
    if (-not $hasRateLimit) {
        $rateLimitJson = @{
            name = "rate-limiting"
            config = @{
                minute = 60
                policy = "local"
            }
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Post -ContentType "application/json" -Body $rateLimitJson | Out-Null
        Write-Host "Attached 'rate-limiting' (60 req/min) plugin." -ForegroundColor Green
    } else {
        Write-Host "'rate-limiting' plugin already attached." -ForegroundColor Gray
    }
} catch {
    Write-Host "Plugin configuration check: $_" -ForegroundColor Yellow
}

# 3. Create Consumer & Credentials
Write-Host "`n[3/5] Configuring Consumer: $consumerName..." -ForegroundColor Yellow
try {
    $existingConsumer = Invoke-RestMethod -Uri "$adminUrl/consumers/$consumerName" -Method Get -ErrorAction SilentlyContinue
    if ($existingConsumer) {
        Write-Host "Consumer $consumerName already exists (ID: $($existingConsumer.id))." -ForegroundColor Green
    }
} catch {
    $consumerJson = @{
        username = $consumerName
        custom_id = "site_dors_va"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$adminUrl/consumers" -Method Post -ContentType "application/json" -Body $consumerJson | Out-Null
    Write-Host "Consumer $consumerName created successfully." -ForegroundColor Green
}

# Add Basic Auth Credential
try {
    $creds = Invoke-RestMethod -Uri "$adminUrl/consumers/$consumerName/basic-auth" -Method Get
    $credExists = $creds.data | Where-Object { $_.username -eq $dorsUsername }
    if (-not $credExists) {
        $credJson = @{
            username = $dorsUsername
            password = $dorsPassword
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$adminUrl/consumers/$consumerName/basic-auth" -Method Post -ContentType "application/json" -Body $credJson | Out-Null
        Write-Host "Added basic-auth credentials ($dorsUsername)." -ForegroundColor Green
    } else {
        Write-Host "Credentials for $dorsUsername already configured." -ForegroundColor Green
    }

    # Assign consumer to dors_group
    $consumerAcls = Invoke-RestMethod -Uri "$adminUrl/consumers/$consumerName/acls" -Method Get
    $hasDorsGroup = $consumerAcls.data | Where-Object { $_.group -eq "dors_group" }
    if (-not $hasDorsGroup) {
        Invoke-RestMethod -Uri "$adminUrl/consumers/$consumerName/acls" -Method Post -Body @{ group = "dors_group" } | Out-Null
        Write-Host "Assigned consumer to ACL group 'dors_group'." -ForegroundColor Green
    }

    # Ensure Service has ACL plugin restricting to dors_group
    $servicePlugins = Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Get
    $hasAcl = $servicePlugins.data | Where-Object { $_.name -eq "acl" }
    if (-not $hasAcl) {
        $aclPayload = @{
            name = "acl"
            config = @{
                allow = @("dors_group")
            }
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Post -ContentType "application/json" -Body $aclPayload | Out-Null
        Write-Host "Attached 'acl' plugin (restricted to 'dors_group')." -ForegroundColor Green
    }
} catch {
    Write-Host "Notice while configuring credentials/ACL: $_" -ForegroundColor Yellow
}

# 4. Define the 4 DORS Routes & Dynamic Translation Payloads
$routes = @(
    @{
        Name = "va-dors-dop-c02-cyclist"
        Paths = @("/va/dors-dop-c02-cyclist", "/api/incidents/translate/vizzio/va/dors_dop_c02_cyclist")
        DeviceName = "DORS Drop-Off Point C02 VA Cyclist Crowding"
        IncidentType = "CYCLIST_GATHERING"
        Webhook = "dors_dop_c02_cyclist"
        Camera = "DORS Drop-Off Point C02"
    },
    @{
        Name = "va-dors-waiting-c03-cyclist"
        Paths = @("/va/dors-waiting-c03-cyclist", "/api/incidents/translate/vizzio/va/dors_waiting_c03_cyclist")
        DeviceName = "DORS Waiting Area C03 VA Cyclist Crowding"
        IncidentType = "CYCLIST_GATHERING"
        Webhook = "dors_waiting_c03_cyclist"
        Camera = "DORS Waiting Area C03"
    },
    @{
        Name = "va-dors-dop-c01-illegal"
        Paths = @("/va/dors-dop-c01-illegal", "/api/incidents/translate/vizzio/va/dors_dop_c01_illegal")
        DeviceName = "DORS Drop-Off Point C01 VA Illegal Parking"
        IncidentType = "ILLEGAL_PARKING"
        Webhook = "dors_dop_c01_illegal"
        Camera = "DORS Drop-Off Point C01"
    },
    @{
        Name = "va-dors-dop-c02-illegal"
        Paths = @("/va/dors-dop-c02-illegal", "/api/incidents/translate/vizzio/va/dors_dop_c02_illegal")
        DeviceName = "DORS Drop-Off Point C02 VA Illegal Parking"
        IncidentType = "ILLEGAL_PARKING"
        Webhook = "dors_dop_c02_illegal"
        Camera = "DORS Drop-Off Point C02"
    }
)

Write-Host "`n[4/5] Configuring 4 DORS Routes & Translator Plugins..." -ForegroundColor Yellow

foreach ($r in $routes) {
    Write-Host "  -> Processing Route: $($r.Name)..." -ForegroundColor Cyan

    $routeId = $null
    try {
        $existingRoute = Invoke-RestMethod -Uri "$adminUrl/routes/$($r.Name)" -Method Get -ErrorAction Stop
        $routeId = $existingRoute.id
        Write-Host "     Route $($r.Name) already exists (ID: $routeId)." -ForegroundColor Gray
    } catch {
        # Create route using JSON
        $routePayload = @{
            name = $r.Name
            paths = $r.Paths
            methods = @("GET", "POST")
            strip_path = $true
        } | ConvertTo-Json

        $routeResp = Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/routes" -Method Post -ContentType "application/json" -Body $routePayload
        $routeId = $routeResp.id
        Write-Host "     Created Route $($r.Name) (ID: $routeId)." -ForegroundColor Green
    }

    # Generate Lua Script
    $luaCode = @"
local now = os.time()
kong.service.request.set_method("POST")
kong.service.request.set_header("Authorization", "$dorsBase64Auth")
kong.service.request.set_header("Content-Type", "application/json")
local b = string.format('{"site":"DORS","deviceName":"$($r.DeviceName)","incidentType":"$($r.IncidentType)","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"$($r.Webhook)","associatedCamera":"$($r.Camera)"}}', now)
kong.service.request.set_raw_body(b)
"@

    # Check plugin on route
    $routePlugins = Invoke-RestMethod -Uri "$adminUrl/routes/$($r.Name)/plugins" -Method Get
    
    # Remove any legacy pre-function plugin if present
    $oldPreFn = $routePlugins.data | Where-Object { $_.name -eq "pre-function" }
    if ($oldPreFn) {
        Invoke-RestMethod -Uri "$adminUrl/plugins/$($oldPreFn.id)" -Method Delete | Out-Null
    }

    $postFn = $routePlugins.data | Where-Object { $_.name -eq "post-function" }
    
    $pluginPayload = @{
        name = "post-function"
        config = @{
            access = @($luaCode)
        }
    } | ConvertTo-Json

    if (-not $postFn) {
        Invoke-RestMethod -Uri "$adminUrl/routes/$($r.Name)/plugins" -Method Post -ContentType "application/json" -Body $pluginPayload | Out-Null
        Write-Host "     Attached 'post-function' translator plugin." -ForegroundColor Green
    } else {
        Invoke-RestMethod -Uri "$adminUrl/plugins/$($postFn.id)" -Method Patch -ContentType "application/json" -Body $pluginPayload | Out-Null
        Write-Host "     Updated 'post-function' translator plugin." -ForegroundColor Green
    }
}

Write-Host "`n[5/5] Verification & Summary:" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Green
Write-Host "✅ DORS VA Configuration Successfully Applied!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "Service:   $serviceName -> $targetUrl"
Write-Host "Consumer:  $consumerName ($dorsUsername)"
Write-Host "`nAvailable Ingress Endpoints (Port 8088):"
foreach ($r in $routes) {
    Write-Host "  • http://localhost:8088$($r.Paths[0])" -ForegroundColor Cyan
}
Write-Host "`nExample Test Command:"
Write-Host 'curl.exe -i -X GET http://localhost:8088/va/dors-dop-c02-cyclist -u "dors_user@isems.com:1Pu1znaPbTqXcyC5KVpP"' -ForegroundColor Yellow
