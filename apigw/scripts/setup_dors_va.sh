#!/usr/bin/env bash
# ==============================================================================
# Automated Kong Gateway Setup Script for Project DORS Video Analytics (VA) Ingress
# ==============================================================================
set -e

ADMIN_URL="${KONG_ADMIN_URL:-http://localhost:8001}"
SERVICE_NAME="imops-dors-incident-service"

# Upstream Host / URL Resolution:
# Usage: ./setup_dors_va.sh [UPSTREAM_HOST_OR_URL]
# Examples:
#   ./setup_dors_va.sh 10.65.51.252
#   ./setup_dors_va.sh 10.65.51.252:13000
#   ./setup_dors_va.sh http://host.docker.internal:13000/api/incidents/monitor
UPSTREAM_INPUT="${1:-${BACKEND_URL:-}}"

if [ -z "$UPSTREAM_INPUT" ]; then
  TARGET_URL="http://10.65.51.252:13000/api/incidents/monitor"
elif [[ "$UPSTREAM_INPUT" =~ ^https?:// ]]; then
  TARGET_URL="$UPSTREAM_INPUT"
elif [[ "$UPSTREAM_INPUT" =~ :[0-9]+ ]]; then
  TARGET_URL="http://${UPSTREAM_INPUT}/api/incidents/monitor"
else
  TARGET_URL="http://${UPSTREAM_INPUT}:13000/api/incidents/monitor"
fi

CONSUMER_NAME="va_dors_consumer"
DORS_USER="dors_user@isems.com"
DORS_PASS="1Pu1znaPbTqXcyC5KVpP"
DORS_AUTH_B64="Basic ZG9yc191c2VyQGlzZW1zLmNvbToxUHUxem5hUGJUcVhjeUM1S1ZwUA=="

echo "===================================================="
echo "🚀 Starting DORS VA Ingress Setup on Kong Gateway"
echo "   Admin URL:    $ADMIN_URL"
echo "   Upstream URL: $TARGET_URL"
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

# Helper function to reliably parse plugin ID from Kong JSON (supports jq, python3, or pure sed)
get_plugin_id() {
  local JSON="$1"
  local PLUGIN_NAME="$2"
  if command -v jq > /dev/null 2>&1; then
    echo "$JSON" | jq -r ".data[]? | select(.name == \"$PLUGIN_NAME\") | .id" 2>/dev/null | head -n 1
  elif command -v python3 > /dev/null 2>&1; then
    echo "$JSON" | python3 -c "import sys, json; data=json.load(sys.stdin).get('data',[]); print(next((p['id'] for p in data if p.get('name')=='$PLUGIN_NAME'), ''))" 2>/dev/null
  else
    echo "$JSON" | sed 's/},{"/\n/g' | grep "\"name\":\"$PLUGIN_NAME\"" | grep -o '"id":"[^"]*"' | head -n 1 | cut -d'"' -f4
  fi
}

# 2. Attach basic-auth, rate-limiting, and acl plugins to Service
echo -e "\n[2/5] Attaching Service Plugins (basic-auth, rate-limiting, acl)..."
SERVICE_PLUGINS=$(curl -s "$ADMIN_URL/services/$SERVICE_NAME/plugins" || echo '{"data":[]}')

# basic-auth
if [ -z "$(get_plugin_id "$SERVICE_PLUGINS" "basic-auth")" ]; then
  curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"basic-auth","config":{"hide_credentials":false}}' > /dev/null || true
  echo "   • Attached 'basic-auth' plugin."
else
  echo "   • 'basic-auth' plugin already attached."
fi

# rate-limiting
if [ -z "$(get_plugin_id "$SERVICE_PLUGINS" "rate-limiting")" ]; then
  curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"rate-limiting","config":{"minute":60,"policy":"local"}}' > /dev/null || true
  echo "   • Attached 'rate-limiting' (60 req/min) plugin."
else
  echo "   • 'rate-limiting' plugin already attached."
fi

# acl
if [ -z "$(get_plugin_id "$SERVICE_PLUGINS" "acl")" ]; then
  curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"acl","config":{"allow":["dors_group"]}}' > /dev/null || true
  echo "   • Attached 'acl' plugin (restricted to 'dors_group')."
else
  echo "   • 'acl' plugin already attached."
fi

# 3. Create Consumer & Credentials
echo -e "\n[3/5] Configuring Consumer: $CONSUMER_NAME..."
CONSUMER_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/consumers/$CONSUMER_NAME" || true)
if [ "$CONSUMER_CHECK" -ne 200 ]; then
  curl -s -X POST "$ADMIN_URL/consumers" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$CONSUMER_NAME\",\"custom_id\":\"site_dors_va\"}" > /dev/null || true
  echo "   • Consumer '$CONSUMER_NAME' created."
else
  echo "   • Consumer '$CONSUMER_NAME' already exists."
fi

CREDS=$(curl -s "$ADMIN_URL/consumers/$CONSUMER_NAME/basic-auth" || echo '{"data":[]}')
if ! echo "$CREDS" | grep -q "\"username\":\"$DORS_USER\""; then
  curl -s -X POST "$ADMIN_URL/consumers/$CONSUMER_NAME/basic-auth" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$DORS_USER\",\"password\":\"$DORS_PASS\"}" > /dev/null || true
  echo "   • Added basic-auth credentials ($DORS_USER)."
else
  echo "   • Credentials for $DORS_USER already configured."
fi

ACLS=$(curl -s "$ADMIN_URL/consumers/$CONSUMER_NAME/acls" || echo '{"data":[]}')
if ! echo "$ACLS" | grep -q '"group":"dors_group"'; then
  curl -s -X POST "$ADMIN_URL/consumers/$CONSUMER_NAME/acls" \
    -H "Content-Type: application/json" \
    -d '{"group":"dors_group"}' > /dev/null || true
  echo "   • Assigned consumer to ACL group 'dors_group'."
else
  echo "   • ACL group 'dors_group' already assigned."
fi

# 4. Helper function to create route + post-function plugin
create_dors_route() {
  local ROUTE_NAME="$1"
  local PATH_PRIMARY="$2"
  local PATH_ALIAS="$3"
  local DEVICE_NAME="$4"
  local INCIDENT_TYPE="$5"
  local WEBHOOK="$6"
  local CAMERA="$7"

  echo "   -> Configuring Route: $ROUTE_NAME..."

  local ROUTE_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/routes/$ROUTE_NAME" || true)
  if [ "$ROUTE_CHECK" -eq 200 ]; then
    echo "      Route '$ROUTE_NAME' exists. Updating paths..."
    curl -s -X PATCH "$ADMIN_URL/routes/$ROUTE_NAME" \
      -H "Content-Type: application/json" \
      -d "{
        \"paths\": [\"$PATH_PRIMARY\", \"$PATH_ALIAS\"],
        \"methods\": [\"GET\", \"POST\"],
        \"strip_path\": true
      }" > /dev/null
  else
    curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/routes" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"$ROUTE_NAME\",
        \"paths\": [\"$PATH_PRIMARY\", \"$PATH_ALIAS\"],
        \"methods\": [\"GET\", \"POST\"],
        \"strip_path\": true
      }" > /dev/null
  fi

  local ROUTE_PLUGINS=$(curl -s "$ADMIN_URL/routes/$ROUTE_NAME/plugins" || echo '{"data":[]}')

  local OLD_PRE_ID=$(get_plugin_id "$ROUTE_PLUGINS" "pre-function")
  if [ -n "$OLD_PRE_ID" ]; then
    curl -s -X DELETE "$ADMIN_URL/plugins/$OLD_PRE_ID" > /dev/null || true
  fi

  local LUA_CODE="local now = os.time(); kong.service.request.set_method('POST'); kong.service.request.set_header('Authorization', '$DORS_AUTH_B64'); kong.service.request.set_header('Content-Type', 'application/json'); local b = string.format('{\"site\":\"DORS\",\"deviceName\":\"$DEVICE_NAME\",\"incidentType\":\"$INCIDENT_TYPE\",\"timestamp\":%d,\"mode\":\"incident\",\"metadata\":{\"source\":\"vizzio_va\",\"webhook\":\"$WEBHOOK\",\"associatedCamera\":\"$CAMERA\"}}', now); kong.service.request.set_raw_body(b);"

  local POST_FN_ID=$(get_plugin_id "$ROUTE_PLUGINS" "post-function")
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

echo -e "\n[4/5] Configuring 4 DORS Routes & Translator Plugins..."

# Route 1: DOP C02 Cyclist
create_dors_route \
  "va-dors-dop-c02-cyclist" \
  "/va/dors-dop-c02-cyclist" \
  "/api/incidents/translate/vizzio/va/dors_dop_c02_cyclist" \
  "DORS Drop-Off Point C02 VA Cyclist Crowding" \
  "CYCLIST_GATHERING" \
  "dors_dop_c02_cyclist" \
  "DORS Drop-Off Point C02"

# Route 2: Waiting Area C03 Cyclist
create_dors_route \
  "va-dors-waiting-c03-cyclist" \
  "/va/dors-waiting-c03-cyclist" \
  "/api/incidents/translate/vizzio/va/dors_waiting_c03_cyclist" \
  "DORS Waiting Area C03 VA Cyclist Crowding" \
  "CYCLIST_GATHERING" \
  "dors_waiting_c03_cyclist" \
  "DORS Waiting Area C03"

# Route 3: DOP C01 Illegal Parking
create_dors_route \
  "va-dors-dop-c01-illegal" \
  "/va/dors-dop-c01-illegal" \
  "/api/incidents/translate/vizzio/va/dors_dop_c01_illegal" \
  "DORS Drop-Off Point C01 VA Illegal Parking" \
  "ILLEGAL_PARKING" \
  "dors_dop_c01_illegal" \
  "DORS Drop-Off Point C01"

# Route 4: DOP C02 Illegal Parking
create_dors_route \
  "va-dors-dop-c02-illegal" \
  "/va/dors-dop-c02-illegal" \
  "/api/incidents/translate/vizzio/va/dors_dop_c02_illegal" \
  "DORS Drop-Off Point C02 VA Illegal Parking" \
  "ILLEGAL_PARKING" \
  "dors_dop_c02_illegal" \
  "DORS Drop-Off Point C02"

echo -e "\n===================================================="
echo "✅ DORS VA Configuration Successfully Applied!"
echo "===================================================="
echo "Service:   $SERVICE_NAME -> $TARGET_URL"
echo "Consumer:  $CONSUMER_NAME ($DORS_USER)"
echo -e "\nAvailable Ingress Endpoints (Port 8088):"
echo "  • http://localhost:8088/va/dors-dop-c02-cyclist"
echo "  • http://localhost:8088/va/dors-waiting-c03-cyclist"
echo "  • http://localhost:8088/va/dors-dop-c01-illegal"
echo "  • http://localhost:8088/va/dors-dop-c02-illegal"
echo -e "\nExample Test Command:"
echo "curl -i -X GET http://localhost:8088/va/dors-dop-c02-cyclist -u \"$DORS_USER:$DORS_PASS\""
