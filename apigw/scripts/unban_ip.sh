#!/usr/bin/env bash
# ==============================================================================
# Manually unban an IP from Kong WAF Lockout
# ==============================================================================

if [ -z "$1" ]; then
    echo "Usage: ./unban_ip.sh <IP_ADDRESS> [REDIS_CONTAINER]"
    exit 1
fi

IP_ADDRESS="$1"
REDIS_CONTAINER="${2:-kong-redis}"

echo "===================================================="
echo "🔓 Unbanning IP from Kong WAF: $IP_ADDRESS"
echo "===================================================="

docker exec "$REDIS_CONTAINER" redis-cli del "waf:ban:$IP_ADDRESS" > /dev/null 2>&1
docker exec "$REDIS_CONTAINER" redis-cli del "waf:rate:$IP_ADDRESS" > /dev/null 2>&1

echo "IP $IP_ADDRESS has been unbanned in Redis container $REDIS_CONTAINER."
