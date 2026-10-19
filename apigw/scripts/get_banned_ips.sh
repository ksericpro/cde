#!/usr/bin/env bash
# ==============================================================================
# Inspect active Kong WAF IP lockouts
# ==============================================================================

REDIS_CONTAINER="${1:-kong-redis}"

echo "===================================================="
echo "🛡️ Kong WAF Lockout Monitor: Active Banned IPs"
echo "===================================================="

KEYS=$(docker exec "$REDIS_CONTAINER" redis-cli keys "waf:ban:*" 2>/dev/null || true)
if [ -z "$KEYS" ]; then
    echo "No active IP lockouts found in Redis."
    exit 0
fi

printf "%-20s %-15s %-15s\n" "IP Address" "Status" "Remaining (s)"
printf "%-20s %-15s %-15s\n" "----------" "------" "-------------"

for key in $KEYS; do
    ip="${key#waf:ban:}"
    ttl=$(docker exec "$REDIS_CONTAINER" redis-cli ttl "$key" 2>/dev/null | tr -d '\r')
    printf "%-20s %-15s %-15s\n" "$ip" "LOCKED" "${ttl}s"
done
