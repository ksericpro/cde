#!/usr/bin/env bash
# ==============================================================================
# Automated Kong Gateway Setup Script for Project DORS Video Analytics (VA) Ingress
# ==============================================================================
set -e

ADMIN_URL="${KONG_ADMIN_URL:-http://localhost:8001}"
SERVICE_NAME="imops-dors-incident-service"
TARGET_URL="${BACKEND_URL:-http://host.docker.internal:13000/api/incidents/monitor}"
CONSUMER_NAME="va_dors_consumer"
DORS_USER="dors_user@isems.com"
DORS_PASS="1Pu1znaPbTqXcyC5KVpP"
DORS_AUTH_B64="Basic ZG9yc191c2VyQGlzZW1zLmNvbToxUHUxem5hUGJUcVhjeUM1S1ZwUA=="

echo "===================================================="
echo "🚀 Starting DORS VA Ingress Setup on Kong Gateway"
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
  -d '{"name":"acl","config":{"allow":["dors_group"]}}' > /dev/null || true
echo "   • acl (dors_group) configured."

# 3. Create Consumer & Credentials
echo -e "\n[3/5] Configuring Consumer: $CONSUMER_NAME..."
curl -s -X POST "$ADMIN_URL/consumers" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$CONSUMER_NAME\",\"custom_id\":\"site_dors_va\"}" > /dev/null || true

curl -s -X POST "$ADMIN_URL/consumers/$CONSUMER_NAME/basic-auth" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$DORS_USER\",\"password\":\"$DORS_PASS\"}" > /dev/null || true

curl -s -X POST "$ADMIN_URL/consumers/$CONSUMER_NAME/acls" \
  -H "Content-Type: application/json" \
  -d '{"group":"dors_group"}' > /dev/null || true
echo "   ✅ Consumer '$CONSUMER_NAME' credentials and ACL configured."

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

  curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/routes" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$ROUTE_NAME\",
      \"paths\": [\"$PATH_PRIMARY\", \"$PATH_ALIAS\"],
      \"methods\": [\"GET\", \"POST\"],
      \"strip_path\": true
    }" > /dev/null || true

  local LUA_CODE="local now = os.time(); kong.service.request.set_method('POST'); kong.service.request.set_header('Authorization', '$DORS_AUTH_B64'); kong.service.request.set_header('Content-Type', 'application/json'); local b = string.format('{\"site\":\"DORS\",\"deviceName\":\"$DEVICE_NAME\",\"incidentType\":\"$INCIDENT_TYPE\",\"timestamp\":%d,\"mode\":\"incident\",\"metadata\":{\"source\":\"vizzio_va\",\"webhook\":\"$WEBHOOK\",\"associatedCamera\":\"$CAMERA\"}}', now); kong.service.request.set_raw_body(b);"

  curl -s -X POST "$ADMIN_URL/routes/$ROUTE_NAME/plugins" \
    -d "name=post-function" \
    --data-urlencode "config.access[]=$LUA_CODE" > /dev/null || true

  echo "      ✅ Route '$ROUTE_NAME' and translator plugin attached."
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
