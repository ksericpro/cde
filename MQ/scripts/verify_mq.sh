#!/usr/bin/env bash
# =============================================================================
#  verify_mq.sh — Smoke test Mosquitto (TCP + WebSockets + ACL) and Cedalo UI
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MQ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$MQ_DIR"

if [ -f ".env" ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_WS_PORT="${MQTT_WS_PORT:-9002}"
MMC_PORT="${MMC_PORT:-8089}"
MQTT_ADMIN_USER="${MQTT_ADMIN_USER:-cedalo}"
MQTT_ADMIN_PASSWORD="${MQTT_ADMIN_PASSWORD:-cdepassword123}"
MQTT_PUBLISHER_USER="${MQTT_PUBLISHER_USER:-cde-publisher}"
MQTT_PUBLISHER_PASSWORD="${MQTT_PUBLISHER_PASSWORD:-cdepublisher123}"

echo "================================================================="
echo "  Verifying CDE Message Queue (Mosquitto + Cedalo MC)            "
echo "================================================================="

echo "[1/5] Checking running containers..."
docker compose ps

echo "[2/5] Verifying anonymous connections are REJECTED..."
if docker exec cde-mosquitto mosquitto_pub -h localhost -p 1883 -t "cde/test" -m "anon" >/dev/null 2>&1; then
  echo "[-] FAIL: Anonymous publish succeeded (should be denied)!"
  exit 1
else
  echo "[+] PASS: Anonymous connection rejected."
fi

echo "[3/5] Verifying per-topic Dynamic Security publish/subscribe..."
TEST_ROLE="verify-healthcheck-role"
TEST_USER="verify-healthcheck-sub"
TEST_PASS="verify-tmp-pass-123"
TEST_PAYLOAD="cde-healthcheck-$(date +%s)"

cleanup_verify_user() {
  docker exec cde-mosquitto sh -c "
    mosquitto_ctrl -h localhost -p 1883 -u \"$MQTT_ADMIN_USER\" -P \"$MQTT_ADMIN_PASSWORD\" dynsec deleteClient \"$TEST_USER\" >/dev/null 2>&1 || true
    mosquitto_ctrl -h localhost -p 1883 -u \"$MQTT_ADMIN_USER\" -P \"$MQTT_ADMIN_PASSWORD\" dynsec deleteRole \"$TEST_ROLE\" >/dev/null 2>&1 || true
  " >/dev/null 2>&1 || true
}
trap cleanup_verify_user EXIT

docker exec cde-mosquitto sh -c "
  mosquitto_ctrl -h localhost -p 1883 -u \"$MQTT_ADMIN_USER\" -P \"$MQTT_ADMIN_PASSWORD\" dynsec createRole \"$TEST_ROLE\" >/dev/null
  mosquitto_ctrl -h localhost -p 1883 -u \"$MQTT_ADMIN_USER\" -P \"$MQTT_ADMIN_PASSWORD\" dynsec addRoleACL \"$TEST_ROLE\" subscribeLiteral 'cde/healthcheck' allow >/dev/null
  mosquitto_ctrl -h localhost -p 1883 -u \"$MQTT_ADMIN_USER\" -P \"$MQTT_ADMIN_PASSWORD\" dynsec createClient \"$TEST_USER\" -p \"$TEST_PASS\" >/dev/null
  mosquitto_ctrl -h localhost -p 1883 -u \"$MQTT_ADMIN_USER\" -P \"$MQTT_ADMIN_PASSWORD\" dynsec addClientRole \"$TEST_USER\" \"$TEST_ROLE\" >/dev/null
"

SUB_OUT="$(mktemp)"
docker exec cde-mosquitto mosquitto_sub -h localhost -p 1883 \
  -u "$TEST_USER" -P "$TEST_PASS" \
  -t "cde/healthcheck" -C 1 -W 5 >"$SUB_OUT" 2>&1 &
SUB_PID=$!
sleep 1

docker exec cde-mosquitto mosquitto_pub -h localhost -p 1883 \
  -u "$MQTT_PUBLISHER_USER" -P "$MQTT_PUBLISHER_PASSWORD" \
  -t "cde/healthcheck" -m "$TEST_PAYLOAD"

wait "$SUB_PID" || true
RECEIVED="$(cat "$SUB_OUT")"
rm -f "$SUB_OUT"
cleanup_verify_user

if [ "$RECEIVED" = "$TEST_PAYLOAD" ]; then
  echo "[+] PASS: Published with '$MQTT_PUBLISHER_USER' & received '$RECEIVED' with topic-scoped subscriber."
else
  echo "[-] FAIL: Expected '$TEST_PAYLOAD', got '$RECEIVED'"
  exit 1
fi

echo "[4/5] Verifying Mosquitto WebSocket listener on host port ${MQTT_WS_PORT} (for Cloudflare Tunnel)..."
WS_STATUS="$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Protocol: mqtt" \
  "http://127.0.0.1:${MQTT_WS_PORT}/" || true)"

if [ "$WS_STATUS" = "101" ]; then
  echo "[+] PASS: WebSocket upgrade returned HTTP 101 Switching Protocols on port ${MQTT_WS_PORT}."
else
  echo "[-] FAIL: Expected HTTP 101 from WebSocket port ${MQTT_WS_PORT}, got HTTP ${WS_STATUS}."
  exit 1
fi

echo "[5/5] Verifying Cedalo Management Center Web UI on http://localhost:${MMC_PORT}..."
UI_STATUS="$(curl -s -L -o /dev/null -w "%{http_code}" "http://127.0.0.1:${MMC_PORT}/" || true)"
if [ "$UI_STATUS" = "200" ]; then
  echo "[+] PASS: Cedalo Management Center UI returned HTTP 200 on port ${MMC_PORT}."
else
  echo "[-] FAIL: Cedalo UI returned HTTP ${UI_STATUS}."
  exit 1
fi

echo "================================================================="
echo "[+] All MQ verification checks passed!"
echo "================================================================="
