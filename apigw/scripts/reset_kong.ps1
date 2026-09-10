<#
.SYNOPSIS
    Reset Kong Gateway: Remove all Plugins, Routes, Services, and Consumers.
.PARAMETER Force
    Skip confirmation prompt and immediately purge all objects.
#>
param(
    [switch]$Force
)

$adminUrl = "http://localhost:8001"

Write-Host "====================================================" -ForegroundColor Red
Write-Host "⚠️  Kong Gateway Reset / Purge Utility" -ForegroundColor Red
Write-Host "   Target Admin API: $adminUrl" -ForegroundColor Gray
Write-Host "====================================================" -ForegroundColor Red

# Check connectivity
try {
    Invoke-RestMethod -Uri "$adminUrl/status" -Method Get -ErrorAction Stop | Out-Null
} catch {
    Write-Host "❌ ERROR: Cannot connect to Kong Admin API at $adminUrl!" -ForegroundColor Red
    exit 1
}

if (-not $Force) {
    $confirm = Read-Host "⚠️  Are you sure you want to DELETE ALL Kong plugins, routes, services, and consumers? (y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "Aborted. No changes made." -ForegroundColor Yellow
        exit 0
    }
}

# 1. Delete Plugins
Write-Host "`n[1/4] Deleting all Plugins..." -ForegroundColor Yellow
$plugins = (Invoke-RestMethod -Uri "$adminUrl/plugins" -Method Get).data
if ($plugins) {
    foreach ($p in $plugins) {
        Write-Host "  • Deleting plugin: $($p.name) ($($p.id))" -ForegroundColor Gray
        Invoke-RestMethod -Uri "$adminUrl/plugins/$($p.id)" -Method Delete | Out-Null
    }
    Write-Host "  ✅ All plugins deleted." -ForegroundColor Green
} else {
    Write-Host "  • No plugins found." -ForegroundColor Gray
}

# 2. Delete Routes
Write-Host "`n[2/4] Deleting all Routes..." -ForegroundColor Yellow
$routes = (Invoke-RestMethod -Uri "$adminUrl/routes" -Method Get).data
if ($routes) {
    foreach ($r in $routes) {
        Write-Host "  • Deleting route: $($r.name) ($($r.id))" -ForegroundColor Gray
        Invoke-RestMethod -Uri "$adminUrl/routes/$($r.id)" -Method Delete | Out-Null
    }
    Write-Host "  ✅ All routes deleted." -ForegroundColor Green
} else {
    Write-Host "  • No routes found." -ForegroundColor Gray
}

# 3. Delete Services
Write-Host "`n[3/4] Deleting all Services..." -ForegroundColor Yellow
$services = (Invoke-RestMethod -Uri "$adminUrl/services" -Method Get).data
if ($services) {
    foreach ($s in $services) {
        Write-Host "  • Deleting service: $($s.name) ($($s.id))" -ForegroundColor Gray
        Invoke-RestMethod -Uri "$adminUrl/services/$($s.id)" -Method Delete | Out-Null
    }
    Write-Host "  ✅ All services deleted." -ForegroundColor Green
} else {
    Write-Host "  • No services found." -ForegroundColor Gray
}

# 4. Delete Consumers
Write-Host "`n[4/4] Deleting all Consumers..." -ForegroundColor Yellow
$consumers = (Invoke-RestMethod -Uri "$adminUrl/consumers" -Method Get).data
if ($consumers) {
    foreach ($c in $consumers) {
        Write-Host "  • Deleting consumer: $($c.username) ($($c.id))" -ForegroundColor Gray
        Invoke-RestMethod -Uri "$adminUrl/consumers/$($c.id)" -Method Delete | Out-Null
    }
    Write-Host "  ✅ All consumers deleted." -ForegroundColor Green
} else {
    Write-Host "  • No consumers found." -ForegroundColor Gray
}

Write-Host "`n====================================================" -ForegroundColor Green
Write-Host "✨ Kong Gateway Reset Complete! All configurations purged." -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
