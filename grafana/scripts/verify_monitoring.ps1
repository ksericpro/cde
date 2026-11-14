# =============================================================================
#  verify_monitoring.ps1 — Verify health and metrics endpoints for monitoring
# =============================================================================
param(
    [string]$PrometheusHost = "http://localhost:9090",
    [string]$GrafanaHost = "http://localhost:3000",
    [string]$NodeExporterHost = "http://localhost:9100",
    [string]$CadvisorHost = "http://localhost:8085",
    [string]$KongAdminHost = "http://localhost:8001",
    [string]$N8nHost = "https://localhost:5678"
)

# Trust self-signed certificates for local HTTPS tests (e.g. n8n proxy)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Verifying CDE Monitoring Infrastructure Endpoints              " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

function Check-Endpoint {
    param([string]$Name, [string]$Url, [int]$ExpectedCode)

    $padding = " " * [Math]::Max(1, 28 - $Name.Length)
    $urlPadding = " " * [Math]::Max(1, 35 - $Url.Length)
    Write-Host -NoNewline "$Name$padding -> $Url$urlPadding"

    try {
        $code = 0
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            $code = [int](& curl.exe -sk -o NUL -w "%{http_code}" --max-time 3 $Url)
        } else {
            $res = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
            $code = $res.StatusCode
        }
        if ($code -eq $ExpectedCode) {
            Write-Host "[PASS] (HTTP $code)" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] (Expected $ExpectedCode, got $code)" -ForegroundColor Red
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
Check-Endpoint -Name "n8n Engine Metrics"     -Url "$N8nHost/metrics"               -ExpectedCode 200

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
