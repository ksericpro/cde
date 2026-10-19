<#
.SYNOPSIS
    Manually unbans an IP address from Kong WAF Lockout.
.DESCRIPTION
    Deletes 'waf:ban:<ip>' and 'waf:rate:<ip>' from Redis.
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$IpAddress,

    [string]$RedisContainer = "kong-redis"
)

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "🔓 Unbanning IP from Kong WAF: $IpAddress" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

try {
    $banKey = "waf:ban:$IpAddress"
    $rateKey = "waf:rate:$IpAddress"

    $res1 = (docker exec $RedisContainer redis-cli del $banKey).Trim()
    $res2 = (docker exec $RedisContainer redis-cli del $rateKey).Trim()

    Write-Host "Keys cleared for IP $IpAddress (Ban key deleted: $res1, Rate key deleted: $res2)." -ForegroundColor Green
    Write-Host "IP $IpAddress is now unbanned and can immediately send requests." -ForegroundColor Green
} catch {
    Write-Host "Failed to unban IP: $_" -ForegroundColor Red
}
