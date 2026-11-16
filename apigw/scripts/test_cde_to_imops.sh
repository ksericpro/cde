#!/usr/bin/env bash
# ==============================================================================
# Sample Test Script: Call iMOPS BACnet Receiver Endpoints Directly from CDE Host
# ==============================================================================
# Usage:
#   ./apigw/scripts/test_cde_to_imops.sh [IMOPS_HOST_PORT]
# Example:
#   ./apigw/scripts/test_cde_to_imops.sh 192.168.50.197:13000
# ==============================================================================

IMOPS_TARGET="${1:-192.168.50.197:13000}"
if [[ ! "$IMOPS_TARGET" =~ ^https?:// ]]; then
    IMOPS_URL="http://${IMOPS_TARGET}"
else
    IMOPS_URL="${IMOPS_TARGET%/}"
fi

IMOPS_USER="dors_user@isems.com"
IMOPS_PASS="1Pu1znaPbTqXcyC5KVpP"

echo "=================================================================="
echo " Testing Outbound Call from CDE -> iMOPS ($IMOPS_URL)"
echo "   Auth User: $IMOPS_USER"
echo "   Site Name: Malaysia International Trade and Exhibition Centre"
echo "   Site Code: OPTERGY-SDC"
echo "=================================================================="

echo -e "\n[1/2] POST $IMOPS_URL/api/v1/sensors/bacnet/controller-status ..."
curl -i -s -X POST "$IMOPS_URL/api/v1/sensors/bacnet/controller-status" \
  -u "${IMOPS_USER}:${IMOPS_PASS}" \
  -H "Content-Type: application/json" \
  -H "User-Agent: cde-bacnet-adapter/1.0" \
  -d '{
    "site_name": "Malaysia International Trade and Exhibition Centre",
    "site_code": "OPTERGY-SDC",
    "gateway_id": "zaarr-bacnet-gw-01",
    "sent_at": "2026-11-16T02:00:00Z",
    "controller": {
      "device_id": 864077,
      "name": "P864-864077",
      "model": "P864",
      "vendor_name": "Optergy",
      "firmware_revision": "2.4.0",
      "ip_address": "192.168.0.160",
      "online": true,
      "communication_status": "online",
      "point_count": 12
    }
  }'

echo -e "\n\n[2/2] POST $IMOPS_URL/api/v1/sensors/bacnet/updates ..."
curl -i -s -X POST "$IMOPS_URL/api/v1/sensors/bacnet/updates" \
  -u "${IMOPS_USER}:${IMOPS_PASS}" \
  -H "Content-Type: application/json" \
  -H "User-Agent: cde-bacnet-adapter/1.0" \
  -d '{
    "site_name": "Malaysia International Trade and Exhibition Centre",
    "site_code": "OPTERGY-SDC",
    "gateway_id": "zaarr-bacnet-gw-01",
    "batch_id": "20261116T020000Z-01",
    "sent_at": "2026-11-16T02:00:00Z",
    "controller": {
      "device_id": 864077,
      "name": "P864-864077",
      "model": "P864",
      "ip_address": "192.168.0.160",
      "online": true,
      "communication_status": "online"
    },
    "sensors": [
      {
        "sensor_id": "AI-101",
        "group": "BW-INT-M",
        "sensor_name": "BW-INT-M (WIRELESS AIR TOUCH DISPLAY)",
        "metric": "Temperature",
        "category": "environmental",
        "value": 23.45,
        "unit": "°C",
        "display_text": "23.45 °C",
        "severity": "normal",
        "is_triggered": false,
        "is_alarm": false,
        "update_type": "poll",
        "updated_at": "2026-11-16T01:59:59.812Z"
      },
      {
        "sensor_id": "BI-1",
        "group": "WD3",
        "sensor_name": "WD3 (WATER LEAK)",
        "metric": "Water detected",
        "category": "safety_security",
        "value": 1,
        "unit": "",
        "display_text": "Water Detected",
        "severity": "alarm",
        "is_triggered": true,
        "is_alarm": true,
        "update_type": "cov",
        "updated_at": "2026-11-16T01:59:59.850Z"
      }
    ]
  }'
echo -e "\n"

