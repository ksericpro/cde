#!/usr/bin/env bash
# ==============================================================================
# End-to-End Test Script: Push into Kong (:8088) -> CDE Adapter (:8090) -> iMOPS
# ==============================================================================
# Usage:
#   ./apigw/scripts/test_kong_to_imops.sh [KONG_BASE_URL] [API_KEY]
# Examples:
#   ./apigw/scripts/test_kong_to_imops.sh
#   ./apigw/scripts/test_kong_to_imops.sh http://localhost:8088
#   ./apigw/scripts/test_kong_to_imops.sh https://isems-office-cde.somesolutions.xyz
# ==============================================================================

set -e

KONG_URL="${1:-http://localhost:8088}"
KONG_URL="${KONG_URL%/}"
API_KEY="${2:-zaarr-bacnet-gw01-key-2026}"

echo "=================================================================="
echo " 🚀 Testing Full Pipeline: Kong ($KONG_URL) -> CDE -> iMOPS"
echo "    Site Name: Malaysia International Trade and Exhibition Centre"
echo "    Site Code: OPTERGY-SDC"
echo "=================================================================="

# 1. Push Controller Discovery / Status via Kong
echo -e "\n[1/3] POST $KONG_URL/api/v1/bacnet/devices (Kong -> CDE -> iMOPS /controller-status)..."
curl -i -s -X POST "$KONG_URL/api/v1/bacnet/devices" \
  -H "Content-Type: application/json" \
  -H "User-Agent: zaarr-bacnet-gw/1.0" \
  -H "X-API-Key: $API_KEY" \
  -d '{
    "gateway_id": "zaarr-bacnet-gw-01",
    "site_name": "Malaysia International Trade and Exhibition Centre",
    "site_code": "OPTERGY-SDC",
    "sent_at": "2026-11-16T02:00:00Z",
    "device": {
      "device_id": 864077,
      "object_name": "P864-864077",
      "model_name": "P864",
      "vendor_name": "Optergy",
      "vendor_id": 515,
      "firmware_revision": "2.4.0",
      "address": "192.168.0.160:47808",
      "online": true,
      "communication_status": "online",
      "point_count": 12,
      "discovered_at": "2026-11-16T00:00:05Z"
    }
  }'

# 2. Push Sensor Telemetry Batch via Kong
echo -e "\n\n[2/3] POST $KONG_URL/api/v1/bacnet/telemetry (Kong -> CDE -> iMOPS /updates)..."
curl -i -s -X POST "$KONG_URL/api/v1/bacnet/telemetry" \
  -H "Content-Type: application/json" \
  -H "User-Agent: zaarr-bacnet-gw/1.0" \
  -H "X-API-Key: $API_KEY" \
  -d '{
    "gateway_id": "zaarr-bacnet-gw-01",
    "site_name": "Malaysia International Trade and Exhibition Centre",
    "site_code": "OPTERGY-SDC",
    "batch_id": "20261116T020000Z-01",
    "sent_at": "2026-11-16T02:00:00Z",
    "count": 2,
    "readings": [
      {
        "timestamp": "2026-11-16T01:59:59.812Z",
        "source_type": "poll",
        "device_id": 864077,
        "device_name": "P864-864077",
        "controller_model": "P864",
        "device_address": "192.168.0.160:47808",
        "object_type": "analog-input",
        "object_instance": 101,
        "object_id": "analog-input:101",
        "short_object_id": "AI-101",
        "point_name": "BW-INT-M (WIRELESS AIR TOUCH DISPLAY)",
        "property_label": "Temperature",
        "dashboard_label": "BW-INT-M",
        "connection_bus": "BG-1000-M (Wireless)",
        "value": 23.45,
        "value_text": "23.45 °C",
        "unit": "°C",
        "unit_id": 62,
        "is_triggered": false,
        "is_alarm": false,
        "quality": "good"
      },
      {
        "timestamp": "2026-11-16T01:59:59.850Z",
        "source_type": "cov",
        "device_id": 864077,
        "device_name": "P864-864077",
        "controller_model": "P864",
        "device_address": "192.168.0.160:47808",
        "object_type": "binary-input",
        "object_instance": 1,
        "object_id": "binary-input:1",
        "short_object_id": "BI-1",
        "point_name": "WD3 (WATER LEAK)",
        "property_label": "Water detected",
        "dashboard_label": "WD3",
        "connection_bus": "IN 1 • Dry Contact (LED 1)",
        "value": 1,
        "value_text": "Water Detected",
        "is_triggered": true,
        "is_alarm": true,
        "quality": "alarm"
      }
    ]
  }'

sleep 2

# 3. Verify CDE -> iMOPS Delivery Status via Kong
echo -e "\n\n[3/3] GET $KONG_URL/api/v1/bacnet/status (Verifying CDE -> iMOPS delivery & Lakehouse counts)..."
curl -s "$KONG_URL/api/v1/bacnet/status" \
  -H "X-API-Key: $API_KEY"
echo -e "\n"
