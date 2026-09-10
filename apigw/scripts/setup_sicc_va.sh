#!/usr/bin/env bash
# ==============================================================================
# Automated Kong Gateway Setup Script for Project SICC Video Analytics (VA) Ingress
# ==============================================================================
set -e

ADMIN_URL="http://localhost:8001"
SERVICE_NAME="imops-sicc-incident-service"
TARGET_URL="http://host.docker.internal:13000/api/incidents/monitor"
CONSUMER_NAME="va_system_consumer"
SICC_USER="vizzio@imops.local"
SICC_PASS="xAJHkkm7m3V5MhtF0xGM"
SICC_AUTH_B64="Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN"

echo "===================================================="
echo "🚀 Starting SICC VA Ingress Setup on Kong Gateway"
echo "===================================================="

# 1. Create or verify Gateway Service
echo -e "\n[1/5] Creating Gateway Service: $SERVICE_NAME..."
curl -s -X POST "$ADMIN_URL/services" \
  -d "name=$SERVICE_NAME" \
  -d "url=$TARGET_URL" > /dev/null || true

# 2. Attach basic-auth, rate-limiting, and acl plugins to Service
echo -e "\n[2/5] Attaching Service Plugins (basic-auth, rate-limiting, acl)..."
curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
  -d "name=basic-auth" \
  -d "config.hide_credentials=false" > /dev/null || true

curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
  -d "name=rate-limiting" \
  -d "config.minute=60" \
  -d "config.policy=local" > /dev/null || true

curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
  -d "name=acl" \
  -d "config.allow[]=sicc_group" > /dev/null || true

# 3. Create Consumer & Credentials
echo -e "\n[3/5] Configuring Consumer: $CONSUMER_NAME..."
curl -s -X POST "$ADMIN_URL/consumers" \
  -d "username=$CONSUMER_NAME" \
  -d "custom_id=site_sicc_va" > /dev/null || true

curl -s -X POST "$ADMIN_URL/consumers/$CONSUMER_NAME/basic-auth" \
  -d "username=$SICC_USER" \
  -d "password=$SICC_PASS" > /dev/null || true

curl -s -X POST "$ADMIN_URL/consumers/$CONSUMER_NAME/acls" \
  -d "group=sicc_group" > /dev/null || true

# 4. Helper function to create route + post-function plugin
create_sicc_route() {
  local ROUTE_NAME="$1"
  local PATH_PRIMARY="$2"
  local PATH_ALIAS="$3"
  local DEVICE_NAME="$4"
  local INCIDENT_TYPE="$5"
  local WEBHOOK="$6"
  local CAMERA="$7"

  echo "  -> Processing Route: $ROUTE_NAME..."

  curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/routes" \
    -d "name=$ROUTE_NAME" \
    -d "paths[]=$PATH_PRIMARY" \
    -d "paths[]=$PATH_ALIAS" \
    -d "methods[]=GET" \
    -d "methods[]=POST" \
    -d "strip_path=true" > /dev/null || true

  local LUA_CODE="local now = os.time(); kong.service.request.set_method('POST'); kong.service.request.set_header('Authorization', '$SICC_AUTH_B64'); kong.service.request.set_header('Content-Type', 'application/json'); local b = string.format('{\"site\":\"SICC\",\"deviceName\":\"$DEVICE_NAME\",\"incidentType\":\"$INCIDENT_TYPE\",\"timestamp\":%d,\"mode\":\"incident\",\"metadata\":{\"source\":\"vizzio_va\",\"webhook\":\"$WEBHOOK\",\"associatedCamera\":\"$CAMERA\"}}', now); kong.service.request.set_raw_body(b);"

  curl -s -X POST "$ADMIN_URL/routes/$ROUTE_NAME/plugins" \
    -d "name=post-function" \
    --data-urlencode "config.access[]=$LUA_CODE" > /dev/null || true
}

echo -e "\n[4/5] Creating SICC Routes & Translator Plugins..."

# Route 1: Crowding
create_sicc_route \
  "va-sicc-crowding-38alt" \
  "/va/sov-38alt-crowding" \
  "/va/sicc-38alt-crowding" \
  "CROWDING_VA-SOV_38ALT_L4_ICC_1" \
  "CROWDING" \
  "crowding_sov_38alt_l4_icc_1" \
  "SOV 38ALT L4 ICC 1"

# Route 2: Loitering
create_sicc_route \
  "va-sicc-loitering-38alt" \
  "/va/sov-38alt-loitering" \
  "/va/sicc-38alt-loitering" \
  "LOITERING_VA-SOV_38ALT_L4_Lift_Lobby" \
  "LOITERING" \
  "loitering_sov_38alt_l4_lift_lobby" \
  "SOV 38ALT L4 Lift Lobby"

echo -e "\n===================================================="
echo "✅ SICC VA Configuration Successfully Applied!"
echo "===================================================="
echo "Service:   $SERVICE_NAME -> $TARGET_URL"
echo "Consumer:  $CONSUMER_NAME ($SICC_USER)"
echo -e "\nAvailable Ingress Endpoints (Port 8088):"
echo "  • http://localhost:8088/va/sov-38alt-crowding"
echo "  • http://localhost:8088/va/sov-38alt-loitering"
echo "  • http://localhost:8088/va/sicc-38alt-crowding"
echo "  • http://localhost:8088/va/sicc-38alt-loitering"
echo -e "\nExample Test Command:"
echo "curl -i -X GET http://localhost:8088/va/sov-38alt-crowding -u \"$SICC_USER:$SICC_PASS\""
