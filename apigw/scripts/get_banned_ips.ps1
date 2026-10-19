<#
.SYNOPSIS
    Queries Kong WAF active IP lockouts and remaining penalty TTLs.
.DESCRIPTION
    Inspects Redis (inside kong-redis container or local port 6379) for active 'waf:ban:*' keys.
#>

param(
    [string]$RedisContainer = "kong-redis"
)

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "🛡️ Kong WAF Lockout Monitor: Active Banned IPs" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

try {
    $keysOutput = docker exec $RedisContainer redis-cli keys "waf:ban:*" 2>$null
    if (-not $keysOutput) {
        Write-Host "No active IP lockouts found in Redis." -ForegroundColor Green
        return
    }

    $lines = $keysOutput -split "`r?`n" | Where-Object { $_ -ne "" }
    Write-Host ("{0,-20} {1,-15} {2,-15}" -f "IP Address", "Status", "Remaining (s)") -ForegroundColor Yellow
    Write-Host ("{0,-20} {1,-15} {2,-15}" -f "----------", "------", "-------------") -ForegroundColor Gray

    foreach ($key in $lines) {
        $ip = $key -replace "^waf:ban:", ""
        $ttl = (docker exec $RedisContainer redis-cli ttl $key).Trim()
        Write-Host ("{0,-20} {1,-15} {2,-15}" -f $ip, "LOCKED", "$ttl s") -ForegroundColor Red
    }
} catch {
    Write-Host "Failed to query Redis container '$RedisContainer': $_" -ForegroundColor Red
}
