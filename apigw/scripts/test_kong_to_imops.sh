#!/usr/bin/env bash
# ==============================================================================
# End-to-End Test: Push into Kong (:8088) -> CDE Adapter (:8090) -> iMOPS (:13000)
# ==============================================================================
# Usage:
#   ./apigw/scripts/test_kong_to_imops.sh [KONG_BASE_URL] [API_KEY]
# Example:
#   ./apigw/scripts/test_kong_to_imops.sh http://localhost:8088
#   ./apigw/scripts/test_kong_to_imops.sh https://isems-office-cde.somesolutions.xyz
# ==============================================================================

KONG_URL="${1:-http://localhost:8088}"
KONG_URL="${KONG_URL%/}"
API_KEY="${2:-zaarr-bacnet-gw01-key-2026}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================================="
echo " Testing Full Flow: Kong ($KONG_URL) -> CDE -> iMOPS"
echo "=================================================================="

echo -e "\n[1/3] Pushing Controller Status into Kong (POST $KONG_URL/api/v1/bacnet/devices)..."
curl -i -s -X POST "$KONG_URL/api/v1/bacnet/devices" \
  -H "Content-Type: application/json" \
  -H "User-Agent: zaarr-bacnet-gw/1.0" \
  -H "X-API-Key: $API_KEY" \
  --data-binary "@$SCRIPT_DIR/fixtures/bacnet_device.json"

echo -e "\n\n[2/3] Pushing Sensor Telemetry into Kong (POST $KONG_URL/api/v1/bacnet/telemetry)..."
curl -i -s -X POST "$KONG_URL/api/v1/bacnet/telemetry" \
  -H "Content-Type: application/json" \
  -H "User-Agent: zaarr-bacnet-gw/1.0" \
  -H "X-API-Key: $API_KEY" \
  --data-binary "@$SCRIPT_DIR/fixtures/bacnet_telemetry.json"

sleep 2

echo -e "\n\n[3/3] Verifying CDE -> iMOPS Delivery Status (GET $KONG_URL/api/v1/bacnet/status)..."
curl -s "$KONG_URL/api/v1/bacnet/status" \
  -H "X-API-Key: $API_KEY"
echo -e "\n"

