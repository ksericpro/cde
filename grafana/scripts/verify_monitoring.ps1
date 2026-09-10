# =============================================================================
#  verify_monitoring.ps1 — Verify health and metrics endpoints for monitoring
# =============================================================================
param(
    [string]$PrometheusHost = "http://localhost:9090",
    [string]$GrafanaHost = "http://localhost:3000",
    [string]$NodeExporterHost = "http://localhost:9100",
    [string]$CadvisorHost = "http://localhost:8080",
    [string]$KongAdminHost = "http://localhost:8001"
)

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Verifying CDE Monitoring Infrastructure Endpoints              " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

function Check-Endpoint {
    param([string]$Name, [string]$Url, [int]$ExpectedCode)

    $padding = " " * [Math]::Max(1, 28 - $Name.Length)
    $urlPadding = " " * [Math]::Max(1, 35 - $Url.Length)
    Write-Host -NoNewline "$Name$padding -> $Url$urlPadding"

    try {
        $res = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        if ($res.StatusCode -eq $ExpectedCode) {
            Write-Host "[PASS] (HTTP $($res.StatusCode))" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] (Expected $ExpectedCode, got $($res.StatusCode))" -ForegroundColor Red
        }
    } catch {
        Write-Host "[FAIL] (Endpoint unreachable)" -ForegroundColor Red
    }
}

Check-Endpoint -Name "Prometheus Ready"       -Url "$PrometheusHost/-/ready"        -ExpectedCode 200
Check-Endpoint -Name "Prometheus Targets"     -Url "$PrometheusHost/api/v1/targets" -ExpectedCode 200
Check-Endpoint -Name "Grafana Health"         -Url "$GrafanaHost/api/health"        -ExpectedCode 200
Check-Endpoint -Name "Node Exporter Metrics"  -Url "$NodeExporterHost/metrics"       -ExpectedCode 200
Check-Endpoint -Name "cAdvisor Health"        -Url "$CadvisorHost/healthz"          -ExpectedCode 200
Check-Endpoint -Name "Kong Gateway Metrics"   -Url "$KongAdminHost/metrics"         -ExpectedCode 200

Write-Host ""
Write-Host "[*] Querying Prometheus active targets..." -ForegroundColor Yellow
try {
    $targets = Invoke-RestMethod -Uri "$PrometheusHost/api/v1/targets" -Method Get -TimeoutSec 3
    foreach ($t in $targets.data.activeTargets) {
        $color = if ($t.health -eq "up") { "Green" } else { "Red" }
        Write-Host "  $($t.labels.job) [$($t.discoveredLabels.__address__)]: $($t.health)" -ForegroundColor $color
    }
} catch {
    Write-Host "  Could not fetch targets from Prometheus." -ForegroundColor Yellow
}

Write-Host "=================================================================" -ForegroundColor Cyan
