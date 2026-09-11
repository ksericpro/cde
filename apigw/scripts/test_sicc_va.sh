#!/usr/bin/env bash
# ==============================================================================
# Automated Smoke & Verification Test Script for SICC (SOV 38ALT) VA Ingress
# Tests all 21 routes, authentication, and rate limiting against Kong Gateway
# ==============================================================================
set -e

GATEWAY_URL="${1:-http://localhost:8088}"
ADMIN_URL="${KONG_ADMIN_URL:-http://localhost:8001}"
USER="vizzio@imops.local"
PASS="xAJHkkm7m3V5MhtF0xGM"

echo "======================================================================"
echo "🧪 Starting SICC (SOV 38ALT) VA Ingress Verification & Testing Suite"
echo "   Gateway Target: $GATEWAY_URL"
echo "   Consumer Auth:  $USER"
echo "======================================================================"

# 1. Health check
echo -e "\n[Step 1/4] Checking Kong Gateway Health..."
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/status" 2>/dev/null || true)
if [ "$STATUS_CODE" -eq 200 ]; then
  echo "✅ Kong Gateway is healthy and running (Admin API :8001)."
else
  echo "⚠️ Kong Admin API not reachable on $ADMIN_URL (continuing with proxy test)."
fi

# 2. Authentication Boundary Tests
echo -e "\n[Step 2/4] Testing Security & Authentication Boundaries..."

# 2a. Missing credentials (Expect 401)
NO_AUTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$GATEWAY_URL/va/sov-38alt-l4-icc-1-crowding" || true)
if [ "$NO_AUTH_CODE" -eq 401 ]; then
  echo "  ✅ Missing Auth: HTTP 401 Unauthorized (Security Enforcement PASS)"
else
  echo "  ❌ Missing Auth: Expected 401, got $NO_AUTH_CODE (FAIL)"
fi

# 2b. Invalid credentials (Expect 401)
BAD_AUTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$GATEWAY_URL/va/sov-38alt-l4-icc-1-crowding" -u "wrong_user:wrong_pass" || true)
if [ "$BAD_AUTH_CODE" -eq 401 ]; then
  echo "  ✅ Invalid Credentials: HTTP 401 Unauthorized (Security Enforcement PASS)"
else
  echo "  ❌ Invalid Credentials: Expected 401, got $BAD_AUTH_CODE (FAIL)"
fi

# 2c. Invalid route / 404 (Expect 404)
NOT_FOUND_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$GATEWAY_URL/va/non-existent-route-test" -u "$USER:$PASS" || true)
if [ "$NOT_FOUND_CODE" -eq 404 ]; then
  echo "  ✅ Unmatched Route: HTTP 404 Not Found (Routing PASS)"
else
  echo "  ⚠️ Unmatched Route: Expected 404, got $NOT_FOUND_CODE"
fi

# 3. Complete 21 Routes Verification
echo -e "\n[Step 3/4] Testing All 21 Production VA Routes (GET & POST)..."

ROUTES=(
  "/va/sov-38alt-l4-icc-1-crowding|CROWDING|SOV 38ALT L4 ICC 1"
  "/va/sov-38alt-l4-lift-lobby-loitering|LOITERING|SOV 38ALT L4 Lift Lobby"
  "/va/sov-38alt-main-gate-smoking|SMOKING|SOV 38ALT Main Gate"
  "/va/sov-38alt-main-gate-fire|FIRE|SOV 38ALT Main Gate"
  "/va/sov-38alt-carpark-lot-1-illegal-parking|ILLEGAL_PARKING|SOV 38ALT Carpark Lot 1"
  "/va/sov-38alt-l1-lift-lobby-loitering|LOITERING|SOV 38ALT L1 Lift Lobby"
  "/va/sov-38alt-l4-corridor-o-s-war-room-loitering|LOITERING|SOV 38ALT L4 Corridor o/s War Room"
  "/va/sov-38alt-l4-interlock-loitering|LOITERING|SOV 38ALT L4 Interlock"
  "/va/sov-38alt-l5-corridor-loitering|LOITERING|SOV 38ALT L5 Corridor"
  "/va/sov-38alt-side-fencing-intrusion|INTRUSION|SOV 38ALT Side Fencing"
  "/va/sov-38alt-side-fencing-smoking|SMOKING|SOV 38ALT Side Fencing"
  "/va/sov-38alt-side-fencing-fire|FIRE|SOV 38ALT Side Fencing"
  "/va/sov-38alt-roof-top-loitering|LOITERING|SOV 38ALT Roof Top"
  "/va/sov-38alt-l2-lift-lobby-loitering|LOITERING|SOV 38ALT L2 Lift Lobby"
  "/va/sov-38alt-l3-lift-lobby-loitering|LOITERING|SOV 38ALT L3 Lift Lobby"
  "/va/sov-38alt-l2-main-lobby-loitering|LOITERING|SOV 38ALT L2 Main Lobby"
  "/va/sov-38alt-l2-reception-loitering|LOITERING|SOV 38ALT L2 Reception"
  "/va/sov-38alt-main-road-loitering|LOITERING|SOV 38ALT Main Road"
  "/va/sov-38alt-l6-lift-lobby-loitering|LOITERING|SOV 38ALT L6 Lift Lobby"
  "/va/sov-38alt-l5-o-s-cyber-room-loitering|LOITERING|SOV 38ALT L5 o/s Cyber Room"
  "/va/sov-38alt-main-gate-perimeter-intrusion|INTRUSION|SOV 38ALT Main Gate Perimeter"
)

TOTAL=0
PASSED=0
FAILED=0

printf "%-4s | %-45s | %-16s | %-8s | %-8s\n" "#" "Route Path" "Incident Type" "GET" "POST"
echo "---------------------------------------------------------------------------------------------"

INDEX=1
for ITEM in "${ROUTES[@]}"; do
  IFS="|" read -r ROUTE_PATH INCIDENT_TYPE CAMERA <<< "$ITEM"
  TOTAL=$((TOTAL + 1))

  # Test GET
  GET_RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$GATEWAY_URL$ROUTE_PATH" -u "$USER:$PASS" || echo "HTTP_CODE:000")
  GET_CODE=$(echo "$GET_RESP" | grep "HTTP_CODE" | cut -d: -f2)

  # Test POST
  POST_RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$GATEWAY_URL$ROUTE_PATH" -u "$USER:$PASS" || echo "HTTP_CODE:000")
  POST_CODE=$(echo "$POST_RESP" | grep "HTTP_CODE" | cut -d: -f2)

  GET_STATUS="❌ $GET_CODE"
  POST_STATUS="❌ $POST_CODE"

  if [ "$GET_CODE" -eq 200 ] || [ "$GET_CODE" -eq 201 ]; then
    GET_STATUS="✅ $GET_CODE"
  fi
  if [ "$POST_CODE" -eq 200 ] || [ "$POST_CODE" -eq 201 ]; then
    POST_STATUS="✅ $POST_CODE"
  fi

  if [[ "$GET_STATUS" =~ "✅" ]] && [[ "$POST_STATUS" =~ "✅" ]]; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
  fi

  printf "%-4s | %-45s | %-16s | %-8s | %-8s\n" "$INDEX" "$ROUTE_PATH" "$INCIDENT_TYPE" "$GET_STATUS" "$POST_STATUS"
  INDEX=$((INDEX + 1))
done

echo "---------------------------------------------------------------------------------------------"
echo "Results Summary: Total: $TOTAL | Passed: $PASSED | Failed: $FAILED"

# 4. Rate Limiting Burst Test
echo -e "\n[Step 4/4] Testing Rate Limiting (60 req/min quota check)..."
echo "  Sending rapid burst of 65 requests to /va/sov-38alt-l4-icc-1-crowding..."
RATE_LIMIT_HIT=0
for i in $(seq 1 65); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$GATEWAY_URL/va/sov-38alt-l4-icc-1-crowding" -u "$USER:$PASS" || true)
  if [ "$CODE" -eq 429 ]; then
    RATE_LIMIT_HIT=$((RATE_LIMIT_HIT + 1))
  fi
done

if [ "$RATE_LIMIT_HIT" -gt 0 ]; then
  echo "  ✅ Rate Limiting Enforcement PASS: Received HTTP 429 Too Many Requests on burst ($RATE_LIMIT_HIT requests throttled)."
else
  echo "  ℹ️ Notice: Burst completed without hitting 429 (check if rate limit counter was clean or limit raised)."
fi

echo -e "\n======================================================================"
echo "🎯 Verification & Testing Suite Completed!"
echo "======================================================================"
