# =============================================================================
#  sync_imops_logs.ps1 — Sync iMOPS Container Logs (imops-backend :13000,
#  imops-worker, imops-frontend) into Elasticsearch (cde-imops-logs-*)
#  Works even when Docker Desktop uses the 'local' binary logging driver!
# =============================================================================
param(
    [string]$EsUrl = "http://localhost:9200",
    [string[]]$Containers = @("imops-backend", "imops-worker", "imops-frontend"),
    [int]$TailLines = 2000,
    [switch]$IncludeHealthChecks
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$dateStr = (Get-Date).ToUniversalTime().ToString("yyyy.MM.dd")
$indexName = "cde-imops-logs-$dateStr"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Syncing iMOPS Application Logs (localhost:13000) to ELK        " -ForegroundColor Cyan
Write-Host "  Target Index: $indexName                                       " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

$sha1 = [System.Security.Cryptography.SHA1]::Create()
$bulkLines = New-Object System.Collections.Generic.List[string]
$totalShipped = 0

foreach ($container in $Containers) {
    $exists = docker ps -q --filter "name=^/${container}$"
    if (-not $exists) {
        Write-Host "[-] Container '$container' is not running, skipping." -ForegroundColor DarkGray
        continue
    }

    $rawLogs = cmd /c "docker logs --tail $TailLines --timestamps $container 2>&1"
    $count = 0

    foreach ($lineObj in $rawLogs) {
        $line = [string]$lineObj
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        # Skip noisy 30s /api/health debug polls unless -IncludeHealthChecks is passed
        if (-not $IncludeHealthChecks -and $line -match '\[DEBUG\] GET /api/health') {
            continue
        }

        # Extract Docker ISO timestamp prefix if present: 2026-11-03T06:07:29.141234567Z <message>
        $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        $msg = $line
        if ($line -match '^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)\s+(.*)$') {
            $ts = $Matches[1]
            $msg = $Matches[2]
        } elseif ($line -match '^\[(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2}\.\d{3})\]\s*(.*)$') {
            $ts = "$($Matches[1])T$($Matches[2])Z"
        }

        # Determine status/level for easy filtering in Kibana
        $status = 200
        if ($msg -match '(?i)\b(error|exception|fail|failed|fatal)\b' -or $msg -match '\b(400|401|403|404|500|502|503)\b') {
            $status = 500
        }

        # Deterministic doc ID so re-running is idempotent
        $hashBytes = $sha1.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("${container}:${ts}:${msg}"))
        $docId = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""

        $meta = @{ index = @{ _index = $indexName; _id = $docId } } | ConvertTo-Json -Compress
        $doc = @{
            "@timestamp" = $ts
            log_source   = "imops-application"
            container    = @{ name = $container }
            service      = @{ name = $container }
            response     = @{ status = $status }
            message      = $msg
        } | ConvertTo-Json -Compress

        $bulkLines.Add($meta)
        $bulkLines.Add($doc)
        $count++
        $totalShipped++

        if ($bulkLines.Count -ge 400) {
            $payload = ($bulkLines -join "`n") + "`n"
            Invoke-RestMethod -Uri "$EsUrl/_bulk" -Method Post -ContentType "application/x-ndjson; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) | Out-Null
            $bulkLines.Clear()
        }
    }

    Write-Host "[+] Collected $count application log events from '$container'" -ForegroundColor Green
}

if ($bulkLines.Count -gt 0) {
    $payload = ($bulkLines -join "`n") + "`n"
    Invoke-RestMethod -Uri "$EsUrl/_bulk" -Method Post -ContentType "application/x-ndjson; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) | Out-Null
    $bulkLines.Clear()
}

Invoke-RestMethod -Uri "$EsUrl/$indexName/_refresh" -Method Post | Out-Null
Write-Host "[+] SUCCESS: Indexed $totalShipped iMOPS application logs into '$indexName'!" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Cyan
