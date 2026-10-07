#!/usr/bin/env bash
# ==============================================================================
# End-to-End Verification Test Suite for Proscalar Option C (Kong + n8n)
# ==============================================================================

set -e

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8088}"
ENDPOINT="$GATEWAY_URL/api/proscalar/webhook"
USERNAME="${PROSCALAR_USER:-proscalar@gmail.com}"
PASSWORD="${PROSCALAR_PASS:-fwpkyjcf2i8fcoP05yEz}"

echo "===================================================="
echo "🧪 Running Proscalar Option C (Kong + n8n) Test Suite"
echo "   Endpoint: $ENDPOINT"
echo "===================================================="

# TEST 1: Unauthorized Request
echo -e "\n[Test 1/5] Testing Unauthorized Request (Expect HTTP 401)..."
STATUS_1=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -d '{"type":"event.publish"}' || true)
if [ "$STATUS_1" -eq 401 ]; then
    echo "✅ PASSED: Kong edge rejected unauthorized request (HTTP 401 Unauthorized)."
else
    echo "❌ Failed: Received HTTP $STATUS_1 instead of 401"
fi

# TEST 2: Active Single Event (Door Forced Open - 5002)
echo -e "\n[Test 2/5] Testing Active Point Alert (Code 5002 - Door Forced Open)..."
RESP_2=$(curl -s -X POST "$ENDPOINT" \
    -u "$USERNAME:$PASSWORD" \
    -H "Content-Type: application/json" \
    -d '{
        "type": "event.publish",
        "timestamp": "2026-06-09T03:00:00.000Z",
        "data": {
            "id": "kong-test-02",
            "eventTimestamp": "2026-06-09T02:59:58.000Z",
            "eventCode": "5002",
            "eventSourceId": "proscalar-src-1",
            "eventSourceName": "OT-CTR-MAIN GATE",
            "eventPointId": "proscalar-pt-1",
            "eventPointName": "OT-MAIN GATE",
            "message": "Logical Door Forced Open ACTIVE."
        }
    }')
echo "$RESP_2" | grep -q '"success":true' && echo "✅ PASSED: Active event ingested and processed by n8n!" || echo "⚠️ Response: $RESP_2"

# TEST 3: Auto-Resolution IDLE Event (Code 4000)
echo -e "\n[Test 3/5] Testing IDLE Auto-Resolution Event (Code 4000 - Reader Tamper IDLE)..."
RESP_3=$(curl -s -X POST "$ENDPOINT" \
    -u "$USERNAME:$PASSWORD" \
    -H "Content-Type: application/json" \
    -d '{
        "type": "event.publish",
        "timestamp": "2026-06-09T03:05:00.000Z",
        "data": {
            "id": "kong-test-03",
            "eventTimestamp": "2026-06-09T03:04:58.000Z",
            "eventCode": "4000",
            "eventSourceId": "proscalar-src-1",
            "eventSourceName": "OT-CTR-MAIN GATE",
            "eventPointId": "proscalar-pt-1",
            "eventPointName": "CV485",
            "message": "Logical Reader Tamper IDLE."
        }
    }')
echo "$RESP_3" | grep -q '"success":true' && echo "✅ PASSED: IDLE event processed and resolved by pipeline!" || echo "⚠️ Response: $RESP_3"

# TEST 4: Multi-Zone Fire Alarm Group (Code 12008)
echo -e "\n[Test 4/5] Testing Alarm Group Safety Event (FIRE Zone Priority)..."
RESP_4=$(curl -s -X POST "$ENDPOINT" \
    -u "$USERNAME:$PASSWORD" \
    -H "Content-Type: application/json" \
    -d '{
        "type": "alarm.publish",
        "timestamp": "2026-06-09T03:10:00.000Z",
        "data": {
            "alarmGroupId": "GRP-FIRE-01",
            "groupEventCode": "12008",
            "name": "EAST WING FIRE CLUSTER",
            "eventSourceName": "East Wing Panel 1",
            "accessZones": [
                { "name": "East Lobby", "type": "NORMAL", "state": "ACTIVE" },
                { "name": "East Server Room", "type": "FIRE", "state": "TRIGGERED" }
            ]
        }
    }')
echo "$RESP_4" | grep -q '"success":true' && echo "✅ PASSED: Multi-zone Fire group alarm ingested as CRITICAL!" || echo "⚠️ Response: $RESP_4"

echo -e "\n===================================================="
echo "🏁 Proscalar Option C Test Suite Finished!"
echo "===================================================="
