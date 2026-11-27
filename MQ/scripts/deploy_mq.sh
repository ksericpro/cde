#!/usr/bin/env bash
# =============================================================================
#  deploy_mq.sh — Initialize Dynamic Security and launch Mosquitto + Cedalo UI
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MQ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$MQ_DIR"

echo "================================================================="
echo "  Deploying CDE Message Queue (Mosquitto + Cedalo MC)            "
echo "  Directory: $MQ_DIR                                             "
echo "================================================================="

# 1. Ensure .env exists
if [ ! -f ".env" ]; then
  echo "[*] .env file not found. Copying from .env.example..."
  cp .env.example .env
fi

# Load environment variables from .env
set -a
# shellcheck disable=SC1091
source .env
set +a

MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_WS_PORT="${MQTT_WS_PORT:-9002}"
MMC_PORT="${MMC_PORT:-8089}"
MQTT_ADMIN_USER="${MQTT_ADMIN_USER:-cedalo}"
MQTT_ADMIN_PASSWORD="${MQTT_ADMIN_PASSWORD:-cdepassword123}"
MQTT_PUBLISHER_USER="${MQTT_PUBLISHER_USER:-cde-publisher}"
MQTT_PUBLISHER_PASSWORD="${MQTT_PUBLISHER_PASSWORD:-cdepublisher123}"
MMC_ADMIN_USER="${MMC_ADMIN_USER:-admin}"

# 2. Check / Create external Docker network 'cde-network'
if ! docker network inspect cde-network >/dev/null 2>&1; then
  echo "[+] Creating external Docker network 'cde-network'..."
  docker network create cde-network >/dev/null
else
  echo "[+] Docker network 'cde-network' already exists."
fi

# 3. Prepare directories
mkdir -p mosquitto/data mosquitto/log management-center/config

# Initialize Cedalo config.json if absent
if [ ! -f "management-center/config/config.json" ]; then
  echo "[+] Creating initial management-center/config/config.json..."
  cat <<'EOF' > management-center/config/config.json
{
  "connections": [],
  "tools": {
    "streamsheets": {
      "instances": []
    }
  },
  "plugins": []
}
EOF
fi

# 4. Initialize Mosquitto Dynamic Security file on first run
FIRST_INIT=false
if [ ! -f "mosquitto/data/dynamic-security.json" ]; then
  FIRST_INIT=true
  echo "[+] Initializing Mosquitto Dynamic Security (admin user: $MQTT_ADMIN_USER)..."
  docker run --rm --user root \
    -v "$MQ_DIR/mosquitto/data:/mosquitto/data" \
    -v "$MQ_DIR/mosquitto/log:/mosquitto/log" \
    eclipse-mosquitto:2 sh -c "
      mosquitto_ctrl dynsec init /mosquitto/data/dynamic-security.json \"$MQTT_ADMIN_USER\" \"$MQTT_ADMIN_PASSWORD\" &&
      chown -R 1883:1883 /mosquitto/data /mosquitto/log &&
      chmod 600 /mosquitto/data/dynamic-security.json
    "
else
  echo "[+] Existing mosquitto/data/dynamic-security.json found; preserving current users/ACLs."
  docker run --rm --user root \
    -v "$MQ_DIR/mosquitto/data:/mosquitto/data" \
    -v "$MQ_DIR/mosquitto/log:/mosquitto/log" \
    eclipse-mosquitto:2 sh -c "chown -R 1883:1883 /mosquitto/data /mosquitto/log"
fi

# 5. Launch containers
echo "[+] Starting containers via docker compose..."
docker compose up -d

# 6. Wait for Mosquitto and ensure default ACLs & cde-publisher exist (idempotent)
echo "[+] Waiting for cde-mosquitto to accept connections..."
for i in $(seq 1 20); do
  if docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 \
    -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec listRoles >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if [ "$FIRST_INIT" = true ] || ! docker exec cde-mosquitto mosquitto_ctrl -h localhost -p 1883 \
  -u "$MQTT_ADMIN_USER" -P "$MQTT_ADMIN_PASSWORD" dynsec listRoles 2>/dev/null | grep -qx "cde-publisher"; then
  echo "[+] Setting default ACLs (publishClientSend=deny, subscribe=deny, publishClientReceive=allow)..."
  docker exec cde-mosquitto sh -c "
    mosquitto_ctrl -h localhost -p 1883 -u \"$MQTT_ADMIN_USER\" -P \"$MQTT_ADMIN_PASSWORD\" dynsec setDefaultACLAccess publishClientSend deny
    mosquitto_ctrl -h localhost -p 1883 -u \"$MQTT_ADMIN_USER\" -P \"$MQTT_ADMIN_PASSWORD\" dynsec setDefaultACLAccess publishClientReceive allow
    mosquitto_ctrl -h localhost -p 1883 -u \"$MQTT_ADMIN_USER\" -P \"$MQTT_ADMIN_PASSWORD\" dynsec setDefaultACLAccess subscribe deny
    mosquitto_ctrl -h localhost -p 1883 -u \"$MQTT_ADMIN_USER\" -P \"$MQTT_ADMIN_PASSWORD\" dynsec setDefaultACLAccess unsubscribe allow
  "

  echo "[+] Creating internal publisher role 'cde-publisher' (publish cde/#) and client '$MQTT_PUBLISHER_USER'..."
  docker exec cde-mosquitto sh -c "
    mosquitto_ctrl -h localhost -p 1883 -u \"$MQTT_ADMIN_USER\" -P \"$MQTT_ADMIN_PASSWORD\" dynsec createRole cde-publisher || true
    mosquitto_ctrl -h localhost -p 1883 -u \"$MQTT_ADMIN_USER\" -P \"$MQTT_ADMIN_PASSWORD\" dynsec addRoleACL cde-publisher publishClientSend 'cde/#' allow || true
    mosquitto_ctrl -h localhost -p 1883 -u \"$MQTT_ADMIN_USER\" -P \"$MQTT_ADMIN_PASSWORD\" dynsec createClient \"$MQTT_PUBLISHER_USER\" -p \"$MQTT_PUBLISHER_PASSWORD\" || true
    mosquitto_ctrl -h localhost -p 1883 -u \"$MQTT_ADMIN_USER\" -P \"$MQTT_ADMIN_PASSWORD\" dynsec addClientRole \"$MQTT_PUBLISHER_USER\" cde-publisher || true
  "
fi

echo ""
echo "[+] CDE Message Queue deployed successfully!"
echo "    - Cedalo Management UI: http://localhost:${MMC_PORT} (user: ${MMC_ADMIN_USER})"
echo "    - Mosquitto MQTT (TCP): mqtt://localhost:${MQTT_PORT} (internal: mqtt://cde-mosquitto:1883)"
echo "    - Mosquitto WebSockets: ws://localhost:${MQTT_WS_PORT} (Cloudflare Tunnel target: http://localhost:${MQTT_WS_PORT})"
echo "    - Default Publisher:    ${MQTT_PUBLISHER_USER} (allowed to publish to cde/#)"
