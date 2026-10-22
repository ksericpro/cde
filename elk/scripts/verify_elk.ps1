# =============================================================================
#  verify_elk.ps1 — Verify Elasticsearch, Logstash, Kibana and Log Ingestion
# =============================================================================
param(
    [string]$EsUrl = "http://localhost:9200",
    [string]$KibanaUrl = "http://localhost:5601",
    [string]$LogstashUrl = "http://localhost:9600"
)

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Verifying CDE Centralized Logging (ELK Stack)                  " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

function Check-Service {
    param([string]$Name, [string]$Url, [int]$Expected = 200)
    try {
        $res = Invoke-WebRequest -Uri $Url -Method Get -UseBasicParsing -TimeoutSec 5
        if ($res.StatusCode -eq $Expected) {
            Write-Host "  [OK] $Name is UP ($Url)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  [FAIL] $Name returned HTTP $($res.StatusCode)" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "  [FAIL] $Name is unreachable at $Url ($($_.Exception.Message))" -ForegroundColor Red
        return $false
    }
}

Check-Service -Name "Elasticsearch Cluster" -Url "$EsUrl/_cluster/health"
Check-Service -Name "Logstash Engine" -Url "$LogstashUrl"
Check-Service -Name "Kibana Web UI" -Url "$KibanaUrl/api/status"

Write-Host "`n[+] Checking Elasticsearch Indices..." -ForegroundColor Yellow
try {
    $indices = Invoke-RestMethod -Uri "$EsUrl/_cat/indices?format=json" -Method Get -TimeoutSec 5
    if ($indices.Count -gt 0) {
        $indices | Select-Object index, health, "docs.count", "store.size" | Format-Table -AutoSize
    } else {
        Write-Host "  No indices created yet. Send traffic through Kong or n8n to generate logs." -ForegroundColor Gray
    }
} catch {
    Write-Host "[-] Could not retrieve indices: $_" -ForegroundColor Red
}

Write-Host "=================================================================" -ForegroundColor Cyan
