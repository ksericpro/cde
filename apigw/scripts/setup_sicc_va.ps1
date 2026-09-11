<#
.SYNOPSIS
    Automated Kong Gateway Setup Script for Project SICC (SOV 38ALT) Video Analytics (VA) Ingress.
.DESCRIPTION
    Creates / Updates:
    - Gateway Service: imops-sicc-incident-service (points to http://host.docker.internal:13000/api/incidents/monitor)
    - Service Plugins: basic-auth, rate-limiting (60 req/min), acl (sicc_group)
    - Consumer: va_system_consumer (credentials: vizzio@imops.local / xAJHkkm7m3V5MhtF0xGM)
    - 21 Routes + post-function dynamic translator plugins:
      Endpoints: /va/sov-38alt-...
#>

param(
    [Parameter(Position = 0)]
    [string]$UpstreamHost = "10.65.51.252"
)

$adminUrl = "http://localhost:8001"
$serviceName = "imops-sicc-incident-service"

# Upstream URL resolution:
if ($UpstreamHost -match '^https?://') {
    $targetUrl = $UpstreamHost
} elseif ($UpstreamHost -match ':\d+$') {
    $targetUrl = "http://${UpstreamHost}/api/incidents/monitor"
} else {
    $targetUrl = "http://${UpstreamHost}:13000/api/incidents/monitor"
}

$consumerName = "va_system_consumer"
$siccUsername = "vizzio@imops.local"
$siccPassword = "xAJHkkm7m3V5MhtF0xGM"
$siccBase64Auth = "Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "🚀 Starting SICC (SOV 38ALT) VA Ingress Setup on Kong Gateway" -ForegroundColor Cyan
Write-Host "   Admin URL:    $adminUrl" -ForegroundColor Gray
Write-Host "   Upstream URL: $targetUrl" -ForegroundColor Gray
Write-Host "====================================================" -ForegroundColor Cyan

# 1. Create or verify Gateway Service
Write-Host "`n[1/5] Configuring Gateway Service: $serviceName..." -ForegroundColor Yellow
try {
    $existingService = Invoke-RestMethod -Uri "$adminUrl/services/$serviceName" -Method Get -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Host "Service $serviceName already exists (ID: $($existingService.id)). Ensuring upstream URL..." -ForegroundColor Green
        Invoke-RestMethod -Uri "$adminUrl/services/$serviceName" -Method Patch -ContentType "application/json" -Body (@{ url = $targetUrl } | ConvertTo-Json) | Out-Null
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

# 2. Attach basic-auth, rate-limiting, and acl plugins to Service
Write-Host "`n[2/5] Attaching Service Plugins (basic-auth, rate-limiting, acl)..." -ForegroundColor Yellow
try {
    $existingPlugins = Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Get
    
    # basic-auth
    $hasBasicAuth = $existingPlugins.data | Where-Object { $_.name -eq "basic-auth" }
    if (-not $hasBasicAuth) {
        $basicAuthJson = @{
            name = "basic-auth"
            config = @{ hide_credentials = $false }
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Post -ContentType "application/json" -Body $basicAuthJson | Out-Null
        Write-Host "Attached 'basic-auth' plugin." -ForegroundColor Green
    } else {
        Write-Host "'basic-auth' plugin already attached." -ForegroundColor Gray
    }

    # rate-limiting
    $hasRateLimit = $existingPlugins.data | Where-Object { $_.name -eq "rate-limiting" }
    if (-not $hasRateLimit) {
        $rateLimitJson = @{
            name = "rate-limiting"
            config = @{ minute = 60; policy = "local" }
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Post -ContentType "application/json" -Body $rateLimitJson | Out-Null
        Write-Host "Attached 'rate-limiting' (60 req/min) plugin." -ForegroundColor Green
    } else {
        Write-Host "'rate-limiting' plugin already attached." -ForegroundColor Gray
    }

    # acl
    $hasAcl = $existingPlugins.data | Where-Object { $_.name -eq "acl" }
    if (-not $hasAcl) {
        $aclJson = @{
            name = "acl"
            config = @{ allow = @("sicc_group") }
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$adminUrl/services/$serviceName/plugins" -Method Post -ContentType "application/json" -Body $aclJson | Out-Null
        Write-Host "Attached 'acl' plugin (restricted to 'sicc_group')." -ForegroundColor Green
    } else {
        Write-Host "'acl' plugin already attached." -ForegroundColor Gray
    }
} catch {
    Write-Host "Plugin configuration notice: $_" -ForegroundColor Yellow
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
        custom_id = "site_sicc_va"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$adminUrl/consumers" -Method Post -ContentType "application/json" -Body $consumerJson | Out-Null
    Write-Host "Consumer $consumerName created successfully." -ForegroundColor Green
}

# Add Basic Auth Credential
try {
    $creds = Invoke-RestMethod -Uri "$adminUrl/consumers/$consumerName/basic-auth" -Method Get
    $credExists = $creds.data | Where-Object { $_.username -eq $siccUsername }
    if (-not $credExists) {
        $credJson = @{
            username = $siccUsername
            password = $siccPassword
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$adminUrl/consumers/$consumerName/basic-auth" -Method Post -ContentType "application/json" -Body $credJson | Out-Null
        Write-Host "Added basic-auth credentials ($siccUsername)." -ForegroundColor Green
    } else {
        Write-Host "Credentials for $siccUsername already configured." -ForegroundColor Green
    }

    # Assign consumer to sicc_group
    $consumerAcls = Invoke-RestMethod -Uri "$adminUrl/consumers/$consumerName/acls" -Method Get
    $hasSiccGroup = $consumerAcls.data | Where-Object { $_.group -eq "sicc_group" }
    if (-not $hasSiccGroup) {
        Invoke-RestMethod -Uri "$adminUrl/consumers/$consumerName/acls" -Method Post -Body @{ group = "sicc_group" } | Out-Null
        Write-Host "Assigned consumer to ACL group 'sicc_group'." -ForegroundColor Green
    }
} catch {
    Write-Host "Notice while configuring credentials/ACL: $_" -ForegroundColor Yellow
}

# Remove legacy pilot routes if present to avoid path collisions
foreach ($legacyName in @("va-sicc-crowding-38alt", "va-sicc-loitering-38alt")) {
    try {
        $legacy = Invoke-RestMethod -Uri "$adminUrl/routes/$legacyName" -Method Get -ErrorAction SilentlyContinue
        if ($legacy) {
            Invoke-RestMethod -Uri "$adminUrl/routes/$legacyName" -Method Delete | Out-Null
            Write-Host "Removed legacy route '$legacyName'." -ForegroundColor Gray
        }
    } catch {}
}

# 4. Define the 21 SICC (SOV 38ALT) Routes & Dynamic Translation Payloads
$routes = @(,
    @{
        Name = "va-sov-38alt-l4-icc-1-crowding"
        Paths = @(
            "/va/sov-38alt-l4-icc-1-crowding",
            "/va/sov-38alt-crowding"
        )
        DeviceName = "SOV 38ALT L4 ICC 1 VA CROWDING"
        IncidentType = "CROWDING"
        Webhook = "crowding_sov_38alt_l4_icc_1"
        Camera = "SOV 38ALT L4 ICC 1"
    },
    @{
        Name = "va-sov-38alt-l4-lift-lobby-loitering"
        Paths = @(
            "/va/sov-38alt-l4-lift-lobby-loitering",
            "/va/sov-38alt-loitering"
        )
        DeviceName = "SOV 38ALT L4 LIFT LOBBY VA LOITERING"
        IncidentType = "LOITERING"
        Webhook = "loitering_sov_38alt_l4_lift_lobby"
        Camera = "SOV 38ALT L4 Lift Lobby"
    },
    @{
        Name = "va-sov-38alt-main-gate-smoking"
        Paths = @("/va/sov-38alt-main-gate-smoking")
        DeviceName = "SOV 38ALT Main Gate VA SMOKING"
        IncidentType = "SMOKING"
        Webhook = "smoking_sov_38alt_main_gate"
        Camera = "SOV 38ALT Main Gate"
    },
    @{
        Name = "va-sov-38alt-main-gate-fire"
        Paths = @("/va/sov-38alt-main-gate-fire")
        DeviceName = "SOV 38ALT Main Gate VA FIRE"
        IncidentType = "FIRE"
        Webhook = "fire_sov_38alt_main_gate"
        Camera = "SOV 38ALT Main Gate"
    },
    @{
        Name = "va-sov-38alt-carpark-lot-1-illegal-parking"
        Paths = @("/va/sov-38alt-carpark-lot-1-illegal-parking")
        DeviceName = "SOV 38ALT Carpark Lot 1 VA ILLEGAL PARKING"
        IncidentType = "ILLEGAL_PARKING"
        Webhook = "illegal_parking_sov_38alt_carpark_lot_1"
        Camera = "SOV 38ALT Carpark Lot 1"
    },
    @{
        Name = "va-sov-38alt-l1-lift-lobby-loitering"
        Paths = @("/va/sov-38alt-l1-lift-lobby-loitering")
        DeviceName = "SOV 38ALT L1 Lift Lobby VA LOITERING"
        IncidentType = "LOITERING"
        Webhook = "loitering_sov_38alt_l1_lift_lobby"
        Camera = "SOV 38ALT L1 Lift Lobby"
    },
    @{
        Name = "va-sov-38alt-l4-corridor-o-s-war-room-loitering"
        Paths = @("/va/sov-38alt-l4-corridor-o-s-war-room-loitering")
        DeviceName = "SOV 38ALT L4 Corridor o/s War Room VA LOITERING"
        IncidentType = "LOITERING"
        Webhook = "loitering_sov_38alt_l4_corridor_o_s_war_room"
        Camera = "SOV 38ALT L4 Corridor o/s War Room"
    },
    @{
        Name = "va-sov-38alt-l4-interlock-loitering"
        Paths = @("/va/sov-38alt-l4-interlock-loitering")
        DeviceName = "SOV 38ALT L4 Interlock VA LOITERING"
        IncidentType = "LOITERING"
        Webhook = "loitering_sov_38alt_l4_interlock"
        Camera = "SOV 38ALT L4 Interlock"
    },
    @{
        Name = "va-sov-38alt-l5-corridor-loitering"
        Paths = @("/va/sov-38alt-l5-corridor-loitering")
        DeviceName = "SOV 38ALT L5 Corridor VA LOITERING"
        IncidentType = "LOITERING"
        Webhook = "loitering_sov_38alt_l5_corridor"
        Camera = "SOV 38ALT L5 Corridor"
    },
    @{
        Name = "va-sov-38alt-side-fencing-intrusion"
        Paths = @("/va/sov-38alt-side-fencing-intrusion")
        DeviceName = "SOV 38ALT Side Fencing VA INTRUSION"
        IncidentType = "INTRUSION"
        Webhook = "intrusion_sov_38alt_side_fencing"
        Camera = "SOV 38ALT Side Fencing"
    },
    @{
        Name = "va-sov-38alt-side-fencing-smoking"
        Paths = @("/va/sov-38alt-side-fencing-smoking")
        DeviceName = "SOV 38ALT Side Fencing VA SMOKING"
        IncidentType = "SMOKING"
        Webhook = "smoking_sov_38alt_side_fencing"
        Camera = "SOV 38ALT Side Fencing"
    },
    @{
        Name = "va-sov-38alt-side-fencing-fire"
        Paths = @("/va/sov-38alt-side-fencing-fire")
        DeviceName = "SOV 38ALT Side Fencing VA FIRE"
        IncidentType = "FIRE"
        Webhook = "fire_sov_38alt_side_fencing"
        Camera = "SOV 38ALT Side Fencing"
    },
    @{
        Name = "va-sov-38alt-roof-top-loitering"
        Paths = @("/va/sov-38alt-roof-top-loitering")
        DeviceName = "SOV 38ALT Roof Top VA LOITERING"
        IncidentType = "LOITERING"
        Webhook = "loitering_sov_38alt_roof_top"
        Camera = "SOV 38ALT Roof Top"
    },
    @{
        Name = "va-sov-38alt-l2-lift-lobby-loitering"
        Paths = @("/va/sov-38alt-l2-lift-lobby-loitering")
        DeviceName = "SOV 38ALT L2 Lift Lobby VA LOITERING"
        IncidentType = "LOITERING"
        Webhook = "loitering_sov_38alt_l2_lift_lobby"
        Camera = "SOV 38ALT L2 Lift Lobby"
    },
    @{
        Name = "va-sov-38alt-l3-lift-lobby-loitering"
        Paths = @("/va/sov-38alt-l3-lift-lobby-loitering")
        DeviceName = "SOV_38ALT_L3_Lift_Lobby VA LOITERING"
        IncidentType = "LOITERING"
        Webhook = "loitering_sov_38alt_l3_lift_lobby"
        Camera = "SOV 38ALT L3 Lift Lobby"
    },
    @{
        Name = "va-sov-38alt-l2-main-lobby-loitering"
        Paths = @("/va/sov-38alt-l2-main-lobby-loitering")
        DeviceName = "SOV 38ALT L2 Main Lobby VA LOITERING"
        IncidentType = "LOITERING"
        Webhook = "loitering_sov_38alt_l2_main_lobby"
        Camera = "SOV 38ALT L2 Main Lobby"
    },
    @{
        Name = "va-sov-38alt-l2-reception-loitering"
        Paths = @("/va/sov-38alt-l2-reception-loitering")
        DeviceName = "SOV_38ALT_L2_Reception VA LOITERING"
        IncidentType = "LOITERING"
        Webhook = "loitering_sov_38alt_l2_reception"
        Camera = "SOV 38ALT L2 Reception"
    },
    @{
        Name = "va-sov-38alt-main-road-loitering"
        Paths = @("/va/sov-38alt-main-road-loitering")
        DeviceName = "SOV 38ALT Main Road VA LOITERING"
        IncidentType = "LOITERING"
        Webhook = "loitering_sov_38alt_main_road"
        Camera = "SOV 38ALT Main Road"
    },
    @{
        Name = "va-sov-38alt-l6-lift-lobby-loitering"
        Paths = @("/va/sov-38alt-l6-lift-lobby-loitering")
        DeviceName = "SOV 38ALT L6 Lift Lobby VA LOITERING"
        IncidentType = "LOITERING"
        Webhook = "loitering_sov_38alt_l6_lift_lobby"
        Camera = "SOV 38ALT L6 Lift Lobby"
    },
    @{
        Name = "va-sov-38alt-l5-o-s-cyber-room-loitering"
        Paths = @("/va/sov-38alt-l5-o-s-cyber-room-loitering")
        DeviceName = "SOV 38ALT L5 o/s Cyber Room VA LOITERING"
        IncidentType = "LOITERING"
        Webhook = "loitering_sov_38alt_l5_o_s_cyber_room"
        Camera = "SOV 38ALT L5 o/s Cyber Room"
    },
    @{
        Name = "va-sov-38alt-main-gate-perimeter-intrusion"
        Paths = @("/va/sov-38alt-main-gate-perimeter-intrusion")
        DeviceName = "SOV 38ALT Main Gate Perimiter VA INTRUSION"
        IncidentType = "INTRUSION"
        Webhook = "intrusion_sov_38alt_main_gate_perimeter"
        Camera = "SOV 38ALT Main Gate Perimeter"
    }
)

Write-Host "`n[4/5] Configuring SICC Routes & Translator Plugins (Total: $($routes.Count))..." -ForegroundColor Yellow

foreach ($r in $routes) {
    Write-Host "  -> Processing Route: $($r.Name)..." -ForegroundColor Cyan

    $routeId = $null
    try {
        $existingRoute = Invoke-RestMethod -Uri "$adminUrl/routes/$($r.Name)" -Method Get -ErrorAction Stop
        $routeId = $existingRoute.id
        Write-Host "     Route $($r.Name) already exists (ID: $routeId). Updating paths..." -ForegroundColor Gray
        $routeUpdatePayload = @{
            paths = $r.Paths
            methods = @("GET", "POST")
            strip_path = $true
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$adminUrl/routes/$routeId" -Method Patch -ContentType "application/json" -Body $routeUpdatePayload | Out-Null
    } catch {
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
kong.service.request.set_header("Authorization", "$siccBase64Auth")
kong.service.request.set_header("Content-Type", "application/json")
local b = string.format('{"site":"SOV @ 38ALT","deviceName":"$($r.DeviceName)","incidentType":"$($r.IncidentType)","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"$($r.Webhook)","associatedCamera":"$($r.Camera)"}}', now)
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
Write-Host "✅ SICC (SOV 38ALT) VA Configuration Successfully Applied! ($($routes.Count) routes)" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "Service:   $serviceName -> $targetUrl"
Write-Host "Consumer:  $consumerName ($siccUsername)"
Write-Host "`nAvailable Ingress Endpoints (Port 8088):"
foreach ($r in $routes) {
    foreach ($p in $r.Paths) {
        Write-Host "  • http://localhost:8088$p" -ForegroundColor Cyan
    }
}
Write-Host "`nExample Test Command:"
Write-Host 'curl.exe -i -X GET http://localhost:8088/va/sov-38alt-l4-icc-1-crowding -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"' -ForegroundColor Yellow
