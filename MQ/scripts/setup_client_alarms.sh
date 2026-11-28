#!/usr/bin/env bash
# =============================================================================
#  setup_client_alarms.sh — Provision 'role-alarms-read' & 'client_alarms'
# =============================================================================
#  Creates / updates:
#    1. Role   : role-alarms-read (subscribePattern 'cde/alarms/#' -> allow)
#    2. Client : client_alarms (password: alarmpass123)
#    3. Assigns role-alarms-read to client_alarms
#    4. Verifies client & role configuration via mosquitto_ctrl
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MQ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CLIENT_USER="${1:-client_alarms}"
CLIENT_PASS="${2:-alarmpass123}"
ROLE_NAME="${3:-role-alarms-read}"
TOPIC_PATTERN="${4:-cde/alarms/#}"

if [ -f "$MQ_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$MQ_DIR/.env"
    set +a
elif [ -f "$MQ_DIR/.env.example" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$MQ_DIR/.env.example"
    set +a
fi

MQTT_ADMIN_USER="${MQTT_ADMIN_USER:-cedalo}"
MQTT_ADMIN_PASSWORD="${MQTT_ADMIN_PASSWORD:-cdepassword123}"

echo "================================================================="
echo "  Provisioning Mosquitto Test Subscriber & Role                  "
echo "    Client User : $CLIENT_USER"
echo "    Password    : $CLIENT_PASS"
echo "    Role        : $ROLE_NAME"
echo "    Topic ACL   : subscribePattern '$TOPIC_PATTERN' (allow)"
echo "================================================================="

echo -e "\n[1/4] Creating role '$ROLE_NAME' and adding subscribePattern ACL for '$TOPIC_PATTERN'..."
docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 \
    -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" \
    dynsec createRole "$ROLE_NAME" 2>/dev/null || true

docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 \
    -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" \
    dynsec addRoleACL "$ROLE_NAME" subscribePattern "$TOPIC_PATTERN" allow 2>/dev/null || true

echo "[2/4] Creating client '$CLIENT_USER' with password '$CLIENT_PASS'..."
docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 \
    -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" \
    dynsec createClient "$CLIENT_USER" -p "$CLIENT_PASS" 2>/dev/null || true

docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 \
    -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" \
    dynsec setClientPassword "$CLIENT_USER" "$CLIENT_PASS" 2>/dev/null || true

echo "[3/4] Assigning role '$ROLE_NAME' to client '$CLIENT_USER'..."
docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 \
    -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" \
    dynsec addClientRole "$CLIENT_USER" "$ROLE_NAME" 2>/dev/null || true

echo "[4/4] Verifying client and role in Mosquitto Dynamic Security:"
echo -e "\n--- Role Details ($ROLE_NAME) ---"
docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 \
    -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" \
    dynsec getRole "$ROLE_NAME"

echo -e "\n--- Client Details ($CLIENT_USER) ---"
docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 \
    -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" \
    dynsec getClient "$CLIENT_USER"

echo -e "\n[+] Done! '$CLIENT_USER' (password: '$CLIENT_PASS') is ready to subscribe to '$TOPIC_PATTERN'."
