#!/usr/bin/env bash
# ==============================================================================
# Automated Kong Gateway Setup Script for Project SICC Video Analytics (VA) Ingress
# ==============================================================================
set -e

ADMIN_URL="${KONG_ADMIN_URL:-http://localhost:8001}"
SERVICE_NAME="imops-sicc-incident-service"
TARGET_URL="${BACKEND_URL:-http://host.docker.internal:13000/api/incidents/monitor}"
CONSUMER_NAME="va_system_consumer"
SICC_USER="vizzio@imops.local"
SICC_PASS="xAJHkkm7m3V5MhtF0xGM"
SICC_AUTH_B64="Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN"

echo "===================================================="
echo "🚀 Starting SICC VA Ingress Setup on Kong Gateway"
echo "   Admin URL:   $ADMIN_URL"
echo "   Target URL:  $TARGET_URL"
echo "===================================================="

# 0. Connectivity Check
echo -e "\n[0/5] Checking connectivity to Kong Admin API ($ADMIN_URL)..."
if ! curl -s -f "$ADMIN_URL/status" > /dev/null 2>&1; then
  echo "❌ ERROR: Cannot connect to Kong Admin API at $ADMIN_URL!"
  echo "   Please check:"
  echo "   1. Is Kong Gateway running? (run: docker ps | grep kong)"
  echo "   2. Is port 8001 open and mapped to localhost?"
  exit 1
fi
echo "✅ Kong Admin API is reachable."

# 1. Create or verify Gateway Service
echo -e "\n[1/5] Configuring Gateway Service: $SERVICE_NAME..."
SERVICE_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/services/$SERVICE_NAME" || true)
if [ "$SERVICE_CHECK" -eq 200 ]; then
  echo "   Service '$SERVICE_NAME' already exists. Updating port and URL..."
  curl -s -X PATCH "$ADMIN_URL/services/$SERVICE_NAME" \
    -H "Content-Type: application/json" \
    -d "{\"url\":\"$TARGET_URL\"}" > /dev/null
  echo "   ✅ Service '$SERVICE_NAME' updated."
else
  CREATE_RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$ADMIN_URL/services" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$SERVICE_NAME\",\"url\":\"$TARGET_URL\"}")
  HTTP_CODE=$(echo "$CREATE_RESP" | grep "HTTP_CODE:" | cut -d: -f2)
  if [ "$HTTP_CODE" -eq 201 ]; then
    echo "   ✅ Service '$SERVICE_NAME' created successfully."
  else
    echo "   ❌ Failed to create service: $CREATE_RESP"
    exit 1
  fi
fi

# 2. Attach basic-auth, rate-limiting, and acl plugins to Service
echo -e "\n[2/5] Attaching Service Plugins (basic-auth, rate-limiting, acl)..."

# basic-auth
curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
  -H "Content-Type: application/json" \
  -d '{"name":"basic-auth","config":{"hide_credentials":false}}' > /dev/null || true
echo "   • basic-auth configured."

# rate-limiting
curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
  -H "Content-Type: application/json" \
  -d '{"name":"rate-limiting","config":{"minute":60,"policy":"local"}}' > /dev/null || true
echo "   • rate-limiting configured."

# acl
curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
  -H "Content-Type: application/json" \
  -d '{"name":"acl","config":{"allow":["sicc_group"]}}' > /dev/null || true
echo "   • acl (sicc_group) configured."

# 3. Create Consumer, Credentials, and ACL Group
echo -e "\n[3/5] Configuring Consumer: $CONSUMER_NAME..."
curl -s -X POST "$ADMIN_URL/consumers" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$CONSUMER_NAME\",\"custom_id\":\"site_sicc_va\"}" > /dev/null || true

curl -s -X POST "$ADMIN_URL/consumers/$CONSUMER_NAME/basic-auth" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$SICC_USER\",\"password\":\"$SICC_PASS\"}" > /dev/null || true

curl -s -X POST "$ADMIN_URL/consumers/$CONSUMER_NAME/acls" \
  -H "Content-Type: application/json" \
  -d '{"group":"sicc_group"}' > /dev/null || true
echo "   ✅ Consumer '$CONSUMER_NAME' credentials and ACL configured."

# 4. Helper function to create route + post-function plugin
create_sicc_route() {
  local ROUTE_NAME="$1"
  local PATH_PRIMARY="$2"
  local PATH_ALIAS="$3"
  local PATH_TRANSLATE="$4"
  local DEVICE_NAME="$5"
  local INCIDENT_TYPE="$6"
  local WEBHOOK="$7"
  local CAMERA="$8"

  echo "   -> Configuring Route: $ROUTE_NAME..."

  # Check if route already exists
  local ROUTE_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/routes/$ROUTE_NAME" || true)
  if [ "$ROUTE_CHECK" -eq 200 ]; then
    echo "      Route '$ROUTE_NAME' exists. Updating paths..."
    curl -s -X PATCH "$ADMIN_URL/routes/$ROUTE_NAME" \
      -H "Content-Type: application/json" \
      -d "{
        \"paths\": [\"$PATH_PRIMARY\", \"$PATH_ALIAS\", \"$PATH_TRANSLATE\"],
        \"methods\": [\"GET\", \"POST\"],
        \"strip_path\": true
      }" > /dev/null
  else
    curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/routes" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"$ROUTE_NAME\",
        \"paths\": [\"$PATH_PRIMARY\", \"$PATH_ALIAS\", \"$PATH_TRANSLATE\"],
        \"methods\": [\"GET\", \"POST\"],
        \"strip_path\": true
      }" > /dev/null
  fi

  # Check existing plugins on this route
  local ROUTE_PLUGINS=$(curl -s "$ADMIN_URL/routes/$ROUTE_NAME/plugins" || echo '{"data":[]}')

  # Remove any legacy pre-function plugin on this route
  local OLD_PRE_ID=$(echo "$ROUTE_PLUGINS" | grep -B 2 '"name":"pre-function"' | grep -o '"id":"[^"]*"' | head -n 1 | cut -d'"' -f4 || true)
  if [ -n "$OLD_PRE_ID" ]; then
    curl -s -X DELETE "$ADMIN_URL/plugins/$OLD_PRE_ID" > /dev/null || true
  fi

  local LUA_CODE="local now = os.time(); kong.service.request.set_method('POST'); kong.service.request.set_header('Authorization', '$SICC_AUTH_B64'); kong.service.request.set_header('Content-Type', 'application/json'); local b = string.format('{\"site\":\"SICC\",\"deviceName\":\"$DEVICE_NAME\",\"incidentType\":\"$INCIDENT_TYPE\",\"timestamp\":%d,\"mode\":\"incident\",\"metadata\":{\"source\":\"vizzio_va\",\"webhook\":\"$WEBHOOK\",\"associatedCamera\":\"$CAMERA\"}}', now); kong.service.request.set_raw_body(b);"

  local POST_FN_ID=$(echo "$ROUTE_PLUGINS" | grep -B 2 '"name":"post-function"' | grep -o '"id":"[^"]*"' | head -n 1 | cut -d'"' -f4 || true)
  if [ -n "$POST_FN_ID" ]; then
    curl -s -X PATCH "$ADMIN_URL/plugins/$POST_FN_ID" \
      --data-urlencode "config.access[]=$LUA_CODE" > /dev/null || true
    echo "      ✅ Route '$ROUTE_NAME' translator plugin updated."
  else
    curl -s -X POST "$ADMIN_URL/routes/$ROUTE_NAME/plugins" \
      -d "name=post-function" \
      --data-urlencode "config.access[]=$LUA_CODE" > /dev/null || true
    echo "      ✅ Route '$ROUTE_NAME' and translator plugin attached."
  fi
}

echo -e "\n[4/5] Configuring SICC Routes & Translator Plugins..."

# Route 1: Crowding
create_sicc_route \
  "va-sicc-crowding-38alt" \
  "/va/sov-38alt-crowding" \
  "/va/sicc-38alt-crowding" \
  "/api/incidents/translate/vizzio/va/crowding_sov_38alt_l4_icc_1" \
  "CROWDING_VA-SOV_38ALT_L4_ICC_1" \
  "CROWDING" \
  "crowding_sov_38alt_l4_icc_1" \
  "SOV 38ALT L4 ICC 1"

# Route 2: Loitering
create_sicc_route \
  "va-sicc-loitering-38alt" \
  "/va/sov-38alt-loitering" \
  "/va/sicc-38alt-loitering" \
  "/api/incidents/translate/vizzio/va/loitering_sov_38alt_l4_lift_lobby" \
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
echo "  • http://localhost:8088/va/sicc-38alt-crowding"
echo "  • http://localhost:8088/api/incidents/translate/vizzio/va/crowding_sov_38alt_l4_icc_1"
echo "  • http://localhost:8088/va/sov-38alt-loitering"
echo "  • http://localhost:8088/va/sicc-38alt-loitering"
echo "  • http://localhost:8088/api/incidents/translate/vizzio/va/loitering_sov_38alt_l4_lift_lobby"
echo -e "\nExample Test Command:"
echo "curl -i -X GET http://localhost:8088/va/sov-38alt-crowding -u \"$SICC_USER:$SICC_PASS\""

