#!/usr/bin/env bash
# =============================================================================
#  enable_kong_logstash.sh — Enable Kong TCP Log Plugin to ship logs to Logstash
# =============================================================================
set -euo pipefail

KONG_ADMIN_URL="${1:-http://localhost:8001}"
LOGSTASH_HOST="${2:-cde-logstash}"
LOGSTASH_PORT="${3:-5000}"

echo "================================================================="
echo "  Enabling TCP Log Plugin on Kong Gateway for ELK Logstash       "
echo "  Kong Admin:     $KONG_ADMIN_URL                                "
echo "  Logstash Host:  $LOGSTASH_HOST:$LOGSTASH_PORT                   "
echo "================================================================="

# Check Kong connection
if ! curl -sf "$KONG_ADMIN_URL/status" > /dev/null; then
  echo "[-] ERROR: Kong Admin API is not reachable at $KONG_ADMIN_URL"
  exit 1
fi

EXISTING_ID=$(curl -sf "$KONG_ADMIN_URL/plugins" | grep -o '"id":"[^"]*","name":"tcp-log"' | head -n1 | cut -d'"' -f4 || true)

PAYLOAD=$(cat <<EOF
{
  "name": "tcp-log",
  "config": {
    "host": "$LOGSTASH_HOST",
    "port": $LOGSTASH_PORT,
    "tls": false,
    "timeout": 10000,
    "keepalive": 60000
  }
}
EOF
)

if [ -n "$EXISTING_ID" ]; then
  echo "[+] tcp-log plugin already exists ($EXISTING_ID). Updating..."
  curl -s -X PATCH "$KONG_ADMIN_URL/plugins/$EXISTING_ID" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" > /dev/null
else
  echo "[+] Enabling global tcp-log plugin..."
  curl -s -X POST "$KONG_ADMIN_URL/plugins" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" > /dev/null
fi

echo "[+] SUCCESS: Kong Gateway is now shipping logs to Logstash!"
echo "================================================================="
