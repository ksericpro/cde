#!/usr/bin/env bash
# ==============================================================================
# Linux / Ubuntu Bash Runner for imops_proscalar.json (6 Webhook Scenarios)
# ==============================================================================
# Usage:
#   ./test_imops_proscalar_collection.sh          # Runs all 6 scenarios
#   ./test_imops_proscalar_collection.sh 1        # Runs scenario 1 only
#   GATEWAY_URL=http://10.99.32.55:8088 ./test_imops_proscalar_collection.sh
# ==============================================================================

set -eo pipefail

SCENARIO="${1:-all}"
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8088}"
ENDPOINT="$GATEWAY_URL/api/proscalar/webhook"
USERNAME="${PROSCALAR_USER:-proscalar@gmail.com}"
PASSWORD="${PROSCALAR_PASS:-fwpkyjcf2i8fcoP05yEz}"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

send_scenario() {
    local num="$1"
    local title="$2"
    local code="$3"
    local expected="$4"
    local payload="$5"

    echo ""
    echo -e "${GRAY}----------------------------------------------------${NC}"
    echo -e "${CYAN}SENDING: ${title}${NC}"
    echo -e "${GRAY}Event Code: ${code}${NC}"
    echo -e "${YELLOW}Expected:   ${expected}${NC}"

    local http_code
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "$ENDPOINT" \
        -u "$USERNAME:$PASSWORD" \
        -H "Content-Type: application/json" \
        -d "$payload")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" -eq 200 ]; then
        echo -e "${GREEN}Status:     [PASSED] HTTP 200 OK${NC}"
        # Extract execution ID or message if jq is available
        if command -v jq >/dev/null 2>&1; then
            local exec_id
            exec_id=$(echo "$body" | jq -r '.executionId // empty')
            local pipeline
            pipeline=$(echo "$body" | jq -r '.pipeline // empty')
            [ -n "$pipeline" ] && echo -e "${GRAY}Pipeline:   ${pipeline}${NC}"
            [ -n "$exec_id" ] && echo -e "${GREEN}Exec ID:    ${exec_id}${NC}"
        else
            echo -e "${GRAY}Body:       ${body}${NC}"
        fi
    else
        echo -e "${RED}Status:     [FAILED] HTTP ${http_code}${NC}"
        echo -e "${RED}Details:    ${body}${NC}"
    fi
}

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}Proscalar Ingress Test Suite (imops_proscalar.json)${NC}"
echo -e "${GRAY}Endpoint:   ${ENDPOINT}${NC}"
echo -e "${GRAY}Target:     Kong Edge Gateway (Port 8088)${NC}"
echo -e "${CYAN}====================================================${NC}"

# SCENARIO 1: Door Forced Open
run_1() {
    send_scenario "1" \
        "1. Door Forced Open (Active Access Alarm)" \
        "5002" \
        "High Severity Incident Created ('Door Force Opened')" \
        '{
          "type": "event.publish",
          "timestamp": "2026-06-09T03:00:00.000Z",
          "data": {
            "id": "mock-access-event-id",
            "eventTimestamp": "2026-06-09T02:59:58.000Z",
            "eventCode": "5002",
            "eventSourceId": "proscalar-test-source-id",
            "eventSourceName": "OT-CTR-MAIN GATE",
            "eventPointId": "proscalar-test-point-id",
            "eventPointName": "OT-MAIN GATE",
            "message": "Logical Door Forced Open ACTIVE.",
            "receivedTimestamp": "2026-06-09T02:59:59Z"
          }
        }'
}

# SCENARIO 2: Reader Tamper
run_2() {
    send_scenario "2" \
        "2. Reader Tamper (Active Tamper Alarm)" \
        "4001" \
        "High Severity Incident Created ('Reader Tamper')" \
        '{
          "type": "event.publish",
          "timestamp": "2026-06-09T03:05:00.000Z",
          "data": {
            "id": "mock-tamper-event-id",
            "eventTimestamp": "2026-06-09T03:04:58.000Z",
            "eventCode": "4001",
            "eventSourceId": "proscalar-test-source-id",
            "eventSourceName": "178",
            "eventPointId": "proscalar-test-point-id",
            "eventPointName": "CV485",
            "message": "Logical Reader Tamper ACTIVE.",
            "receivedTimestamp": "2026-06-09T03:04:59Z"
          }
        }'
}

# SCENARIO 3: Reader Tamper Idle
run_3() {
    send_scenario "3" \
        "3. Reader Tamper Idle (Auto-Resolve Code 4001)" \
        "4000" \
        "Auto-resolves open Reader Tamper incident (No new alarm card)" \
        '{
          "type": "event.publish",
          "timestamp": "2026-06-09T03:10:00.000Z",
          "data": {
            "id": "mock-tamper-idle-id",
            "eventTimestamp": "2026-06-09T03:09:58.000Z",
            "eventCode": "4000",
            "eventSourceId": "proscalar-test-source-id",
            "eventSourceName": "178",
            "eventPointId": "proscalar-test-point-id",
            "eventPointName": "CV485",
            "message": "Logical Reader Tamper IDLE.",
            "receivedTimestamp": "2026-06-09T03:09:59Z"
          }
        }'
}

# SCENARIO 4: Fire Alarm Group
run_4() {
    send_scenario "4" \
        "4. Fire Alarm Group (Multi-Zone Fire Aggregation)" \
        "12008" \
        "CRITICAL Incident Created ('Fire Alarm' - Safety Override)" \
        '{
          "type": "alarm.publish",
          "timestamp": "2026-06-09T03:15:00.000Z",
          "data": {
            "alarmGroupId": "mock-alarm-group-id-99",
            "groupEventCode": "12008",
            "name": "FIRE SIGNAL ALARM GROUP",
            "msg": "Alarm Monitoring Group Alarm. Alarm Zone OT-OPEN AREA",
            "eventSourceId": "proscalar-test-source-id",
            "eventSourceName": "OT-CTR-DOOR 1",
            "eventTimestamp": "2026-06-09T03:14:58.000Z",
            "accessZones": [
              {
                "alarmZoneId": "mock-zone-id-a",
                "name": "ZONE A",
                "type": "FIRE",
                "state": "TRIGGERED",
                "eventCode": "12000"
              },
              {
                "alarmZoneId": "mock-zone-id-b",
                "name": "ZONE B",
                "type": "INSTANT",
                "state": "TRIGGERED",
                "eventCode": "12000"
              }
            ]
          }
        }'
}

# SCENARIO 5: AC Power Failure
run_5() {
    send_scenario "5" \
        "5. AC Power Failure (Hardware Alarm)" \
        "1000" \
        "High Severity Incident Created ('Power Failure')" \
        '{
          "type": "event.publish",
          "timestamp": "2026-06-09T03:20:00.000Z",
          "data": {
            "id": "mock-power-failure-id",
            "eventTimestamp": "2026-06-09T03:19:58.000Z",
            "eventCode": "1000",
            "eventSourceId": "proscalar-test-source-id",
            "eventSourceName": "OT-CTR-MAIN GATE",
            "eventPointId": "proscalar-test-point-id",
            "eventPointName": "Main Enclosure Power",
            "message": "Controller AC Power Failure ACTIVE.",
            "receivedTimestamp": "2026-06-09T03:19:59Z"
          }
        }'
}

# SCENARIO 6: Emergency Door Release
run_6() {
    send_scenario "6" \
        "6. Emergency Door Release (Device-Level Safety Button)" \
        "5014" \
        "CRITICAL Incident Created ('Emergency Exit Opened')" \
        '{
          "type": "event.publish",
          "timestamp": "2026-06-09T03:25:00.000Z",
          "data": {
            "id": "mock-emergency-release-id",
            "eventTimestamp": "2026-06-09T03:24:58.000Z",
            "eventCode": "5014",
            "eventSourceId": "proscalar-test-source-id",
            "eventSourceName": "OT-CTR-MAIN GATE",
            "eventPointId": "proscalar-test-point-id",
            "eventPointName": "EMERGENCY DOOR RELEASE BUTTON",
            "message": "Emergency Exit Button Pressed ACTIVE.",
            "receivedTimestamp": "2026-06-09T03:24:59Z"
          }
        }'
}

case "$SCENARIO" in
    1) run_1 ;;
    2) run_2 ;;
    3) run_3 ;;
    4) run_4 ;;
    5) run_5 ;;
    6) run_6 ;;
    all)
        run_1
        sleep 0.3
        run_2
        sleep 0.3
        run_3
        sleep 0.3
        run_4
        sleep 0.3
        run_5
        sleep 0.3
        run_6
        ;;
    *)
        echo -e "${YELLOW}Please specify scenario 1, 2, 3, 4, 5, 6, or 'all'.${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}Finished! View executions in n8n (Executions tab).${NC}"
echo -e "${CYAN}====================================================${NC}"
