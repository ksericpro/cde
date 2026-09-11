#!/usr/bin/env bash
# ==============================================================================
# Automated Kong Gateway Setup Script for Project SICC (SOV 38ALT) Video Analytics (VA) Ingress
# ==============================================================================
set -e

ADMIN_URL="${KONG_ADMIN_URL:-http://localhost:8001}"
SERVICE_NAME="imops-sicc-incident-service"

# Upstream Host / URL Resolution:
# Usage: ./setup_sicc_va.sh [UPSTREAM_HOST_OR_URL]
# Examples:
#   ./setup_sicc_va.sh 10.65.51.252
#   ./setup_sicc_va.sh 10.65.51.252:13000
#   ./setup_sicc_va.sh http://host.docker.internal:13000/api/incidents/monitor
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

CONSUMER_NAME="va_system_consumer"
SICC_USER="vizzio@imops.local"
SICC_PASS="xAJHkkm7m3V5MhtF0xGM"
SICC_AUTH_B64="Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN"

echo "===================================================="
echo "🚀 Starting SICC (SOV 38ALT) VA Ingress Setup on Kong Gateway"
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
  HTTP_CODE=$(echo "$CREATE_RESP" | grep "HTTP_CODE" | cut -d: -f2)
  if [ "$HTTP_CODE" -eq 201 ]; then
    echo "   ✅ Service '$SERVICE_NAME' created."
  else
    echo "   ⚠️ Notice: Service response: $CREATE_RESP"
  fi
fi

# Helper function to check if plugin exists in JSON list
get_plugin_id() {
  local PLUGINS_JSON="$1"
  local PLUGIN_NAME="$2"
  echo "$PLUGINS_JSON" | grep -o '{"id":"[^"]*","name":"'"$PLUGIN_NAME"'"' | cut -d'"' -f4 || true
}

# 2. Attach Plugins to Service: basic-auth, rate-limiting, acl
echo -e "\n[2/5] Attaching Service Plugins (basic-auth, rate-limiting, acl)..."
SERVICE_PLUGINS=$(curl -s "$ADMIN_URL/services/$SERVICE_NAME/plugins" || echo '{"data":[]}')

# 2a. basic-auth
BASIC_AUTH_ID=$(get_plugin_id "$SERVICE_PLUGINS" "basic-auth")
if [ -z "$BASIC_AUTH_ID" ]; then
  curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"basic-auth","config":{"hide_credentials":false}}' > /dev/null || true
  echo "   • Attached 'basic-auth' plugin (hide_credentials=false)."
else
  echo "   • Plugin 'basic-auth' already attached."
fi

# 2b. rate-limiting
RATE_LIMIT_ID=$(get_plugin_id "$SERVICE_PLUGINS" "rate-limiting")
if [ -z "$RATE_LIMIT_ID" ]; then
  curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"rate-limiting","config":{"minute":60,"policy":"local"}}' > /dev/null || true
  echo "   • Attached 'rate-limiting' plugin (60 req/min)."
else
  echo "   • Plugin 'rate-limiting' already attached."
fi

# 2c. acl
ACL_ID=$(get_plugin_id "$SERVICE_PLUGINS" "acl")
if [ -z "$ACL_ID" ]; then
  curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"acl","config":{"allow":["sicc_group"]}}' > /dev/null || true
  echo "   • Attached 'acl' plugin (restricted to 'sicc_group')."
else
  echo "   • Plugin 'acl' already attached."
fi

# 3. Create Consumer & Credentials
echo -e "\n[3/5] Configuring Consumer: $CONSUMER_NAME..."
CONSUMER_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/consumers/$CONSUMER_NAME" || true)
if [ "$CONSUMER_CHECK" -ne 200 ]; then
  curl -s -X POST "$ADMIN_URL/consumers" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$CONSUMER_NAME\",\"custom_id\":\"site_sicc_va\"}" > /dev/null || true
  echo "   • Consumer '$CONSUMER_NAME' created."
else
  echo "   • Consumer '$CONSUMER_NAME' already exists."
fi

CREDS=$(curl -s "$ADMIN_URL/consumers/$CONSUMER_NAME/basic-auth" || echo '{"data":[]}')
if ! echo "$CREDS" | grep -q ""username":"$SICC_USER""; then
  curl -s -X POST "$ADMIN_URL/consumers/$CONSUMER_NAME/basic-auth" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$SICC_USER\",\"password\":\"$SICC_PASS\"}" > /dev/null || true
  echo "   • Added Basic Auth credentials for '$SICC_USER'."
else
  echo "   • Basic Auth credentials for '$SICC_USER' already configured."
fi

ACLS=$(curl -s "$ADMIN_URL/consumers/$CONSUMER_NAME/acls" || echo '{"data":[]}')
if ! echo "$ACLS" | grep -q '"group":"sicc_group"'; then
  curl -s -X POST "$ADMIN_URL/consumers/$CONSUMER_NAME/acls" \
    -H "Content-Type: application/json" \
    -d '{"group":"sicc_group"}' > /dev/null || true
  echo "   • Assigned consumer to ACL group 'sicc_group'."
else
  echo "   • ACL group 'sicc_group' already assigned."
fi

# Remove legacy pilot routes if present
for LEGACY in "va-sicc-crowding-38alt" "va-sicc-loitering-38alt"; do
  curl -s -X DELETE "$ADMIN_URL/routes/$LEGACY" > /dev/null 2>&1 || true
done

# 4. Helper function to create route + post-function plugin
create_sicc_route() {
  local ROUTE_NAME="$1"
  local PATHS_JSON="$2"
  local DEVICE_NAME="$3"
  local INCIDENT_TYPE="$4"
  local WEBHOOK="$5"
  local CAMERA="$6"

  echo "   -> Configuring Route: $ROUTE_NAME..."

  # Check if route already exists
  local ROUTE_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/routes/$ROUTE_NAME" || true)
  if [ "$ROUTE_CHECK" -eq 200 ]; then
    echo "      Route '$ROUTE_NAME' exists. Updating paths..."
    curl -s -X PATCH "$ADMIN_URL/routes/$ROUTE_NAME" \
      -H "Content-Type: application/json" \
      -d "{
        \"paths\": $PATHS_JSON,
        \"methods\": [\"GET\", \"POST\"],
        \"strip_path\": true
      }" > /dev/null
  else
    curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/routes" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"$ROUTE_NAME\",
        \"paths\": $PATHS_JSON,
        \"methods\": [\"GET\", \"POST\"],
        \"strip_path\": true
      }" > /dev/null
  fi

  # Check existing plugins on this route
  local ROUTE_PLUGINS=$(curl -s "$ADMIN_URL/routes/$ROUTE_NAME/plugins" || echo '{"data":[]}')

  # Remove any legacy pre-function plugin on this route
  local OLD_PRE_ID=$(get_plugin_id "$ROUTE_PLUGINS" "pre-function")
  if [ -n "$OLD_PRE_ID" ]; then
    curl -s -X DELETE "$ADMIN_URL/plugins/$OLD_PRE_ID" > /dev/null || true
  fi

  local LUA_CODE="local now = os.time(); kong.service.request.set_method('POST'); kong.service.request.set_header('Authorization', '$SICC_AUTH_B64'); kong.service.request.set_header('Content-Type', 'application/json'); local b = string.format('{\"site\":\"SOV 38ALT\",\"deviceName\":\"$DEVICE_NAME\",\"incidentType\":\"$INCIDENT_TYPE\",\"timestamp\":%d,\"mode\":\"incident\",\"metadata\":{\"source\":\"vizzio_va\",\"webhook\":\"$WEBHOOK\",\"associatedCamera\":\"$CAMERA\"}}', now); kong.service.request.set_raw_body(b);"

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

echo -e "\n[4/5] Configuring SICC (SOV 38ALT) Routes & Translator Plugins (Total: 21)..."

# Route 1: CROWDING
create_sicc_route \
  "va-sov-38alt-l4-icc-1-crowding" \
  '["/va/sov-38alt-l4-icc-1-crowding", "/va/sov-38alt-crowding"]' \
  "SOV 38ALT L4 ICC 1 VA CROWDING" \
  "CROWDING" \
  "crowding_sov_38alt_l4_icc_1" \
  "SOV 38ALT L4 ICC 1"

# Route 2: LOITERING
create_sicc_route \
  "va-sov-38alt-l4-lift-lobby-loitering" \
  '["/va/sov-38alt-l4-lift-lobby-loitering", "/va/sov-38alt-loitering"]' \
  "SOV 38ALT L4 LIFT LOBBY VA LOITERING" \
  "LOITERING" \
  "loitering_sov_38alt_l4_lift_lobby" \
  "SOV 38ALT L4 Lift Lobby"

# Route 3: SMOKING
create_sicc_route \
  "va-sov-38alt-main-gate-smoking" \
  '["/va/sov-38alt-main-gate-smoking"]' \
  "SOV 38ALT Main Gate VA SMOKING" \
  "SMOKING" \
  "smoking_sov_38alt_main_gate" \
  "SOV 38ALT Main Gate"

# Route 4: FIRE
create_sicc_route \
  "va-sov-38alt-main-gate-fire" \
  '["/va/sov-38alt-main-gate-fire"]' \
  "SOV 38ALT Main Gate VA FIRE" \
  "FIRE" \
  "fire_sov_38alt_main_gate" \
  "SOV 38ALT Main Gate"

# Route 5: ILLEGAL_PARKING
create_sicc_route \
  "va-sov-38alt-carpark-lot-1-illegal-parking" \
  '["/va/sov-38alt-carpark-lot-1-illegal-parking"]' \
  "SOV 38ALT Carpark Lot 1 VA ILLEGAL PARKING" \
  "ILLEGAL_PARKING" \
  "illegal_parking_sov_38alt_carpark_lot_1" \
  "SOV 38ALT Carpark Lot 1"

# Route 6: LOITERING
create_sicc_route \
  "va-sov-38alt-l1-lift-lobby-loitering" \
  '["/va/sov-38alt-l1-lift-lobby-loitering"]' \
  "SOV 38ALT L1 Lift Lobby VA LOITERING" \
  "LOITERING" \
  "loitering_sov_38alt_l1_lift_lobby" \
  "SOV 38ALT L1 Lift Lobby"

# Route 7: LOITERING
create_sicc_route \
  "va-sov-38alt-l4-corridor-o-s-war-room-loitering" \
  '["/va/sov-38alt-l4-corridor-o-s-war-room-loitering"]' \
  "SOV 38ALT L4 Corridor o/s War Room VA LOITERING" \
  "LOITERING" \
  "loitering_sov_38alt_l4_corridor_o_s_war_room" \
  "SOV 38ALT L4 Corridor o/s War Room"

# Route 8: LOITERING
create_sicc_route \
  "va-sov-38alt-l4-interlock-loitering" \
  '["/va/sov-38alt-l4-interlock-loitering"]' \
  "SOV 38ALT L4 Interlock VA LOITERING" \
  "LOITERING" \
  "loitering_sov_38alt_l4_interlock" \
  "SOV 38ALT L4 Interlock"

# Route 9: LOITERING
create_sicc_route \
  "va-sov-38alt-l5-corridor-loitering" \
  '["/va/sov-38alt-l5-corridor-loitering"]' \
  "SOV 38ALT L5 Corridor VA LOITERING" \
  "LOITERING" \
  "loitering_sov_38alt_l5_corridor" \
  "SOV 38ALT L5 Corridor"

# Route 10: INTRUSION
create_sicc_route \
  "va-sov-38alt-side-fencing-intrusion" \
  '["/va/sov-38alt-side-fencing-intrusion"]' \
  "SOV 38ALT Side Fencing VA INTRUSION" \
  "INTRUSION" \
  "intrusion_sov_38alt_side_fencing" \
  "SOV 38ALT Side Fencing"

# Route 11: SMOKING
create_sicc_route \
  "va-sov-38alt-side-fencing-smoking" \
  '["/va/sov-38alt-side-fencing-smoking"]' \
  "SOV 38ALT Side Fencing VA SMOKING" \
  "SMOKING" \
  "smoking_sov_38alt_side_fencing" \
  "SOV 38ALT Side Fencing"

# Route 12: FIRE
create_sicc_route \
  "va-sov-38alt-side-fencing-fire" \
  '["/va/sov-38alt-side-fencing-fire"]' \
  "SOV 38ALT Side Fencing VA FIRE" \
  "FIRE" \
  "fire_sov_38alt_side_fencing" \
  "SOV 38ALT Side Fencing"

# Route 13: LOITERING
create_sicc_route \
  "va-sov-38alt-roof-top-loitering" \
  '["/va/sov-38alt-roof-top-loitering"]' \
  "SOV 38ALT Roof Top VA LOITERING" \
  "LOITERING" \
  "loitering_sov_38alt_roof_top" \
  "SOV 38ALT Roof Top"

# Route 14: LOITERING
create_sicc_route \
  "va-sov-38alt-l2-lift-lobby-loitering" \
  '["/va/sov-38alt-l2-lift-lobby-loitering"]' \
  "SOV 38ALT L2 Lift Lobby VA LOITERING" \
  "LOITERING" \
  "loitering_sov_38alt_l2_lift_lobby" \
  "SOV 38ALT L2 Lift Lobby"

# Route 15: LOITERING
create_sicc_route \
  "va-sov-38alt-l3-lift-lobby-loitering" \
  '["/va/sov-38alt-l3-lift-lobby-loitering"]' \
  "SOV_38ALT_L3_Lift_Lobby VA LOITERING" \
  "LOITERING" \
  "loitering_sov_38alt_l3_lift_lobby" \
  "SOV 38ALT L3 Lift Lobby"

# Route 16: LOITERING
create_sicc_route \
  "va-sov-38alt-l2-main-lobby-loitering" \
  '["/va/sov-38alt-l2-main-lobby-loitering"]' \
  "SOV 38ALT L2 Main Lobby VA LOITERING" \
  "LOITERING" \
  "loitering_sov_38alt_l2_main_lobby" \
  "SOV 38ALT L2 Main Lobby"

# Route 17: LOITERING
create_sicc_route \
  "va-sov-38alt-l2-reception-loitering" \
  '["/va/sov-38alt-l2-reception-loitering"]' \
  "SOV_38ALT_L2_Reception VA LOITERING" \
  "LOITERING" \
  "loitering_sov_38alt_l2_reception" \
  "SOV 38ALT L2 Reception"

# Route 18: LOITERING
create_sicc_route \
  "va-sov-38alt-main-road-loitering" \
  '["/va/sov-38alt-main-road-loitering"]' \
  "SOV 38ALT Main Road VA LOITERING" \
  "LOITERING" \
  "loitering_sov_38alt_main_road" \
  "SOV 38ALT Main Road"

# Route 19: LOITERING
create_sicc_route \
  "va-sov-38alt-l6-lift-lobby-loitering" \
  '["/va/sov-38alt-l6-lift-lobby-loitering"]' \
  "SOV 38ALT L6 Lift Lobby VA LOITERING" \
  "LOITERING" \
  "loitering_sov_38alt_l6_lift_lobby" \
  "SOV 38ALT L6 Lift Lobby"

# Route 20: LOITERING
create_sicc_route \
  "va-sov-38alt-l5-o-s-cyber-room-loitering" \
  '["/va/sov-38alt-l5-o-s-cyber-room-loitering"]' \
  "SOV 38ALT L5 o/s Cyber Room VA LOITERING" \
  "LOITERING" \
  "loitering_sov_38alt_l5_o_s_cyber_room" \
  "SOV 38ALT L5 o/s Cyber Room"

# Route 21: INTRUSION
create_sicc_route \
  "va-sov-38alt-main-gate-perimeter-intrusion" \
  '["/va/sov-38alt-main-gate-perimeter-intrusion"]' \
  "SOV 38ALT Main Gate Perimiter VA INTRUSION" \
  "INTRUSION" \
  "intrusion_sov_38alt_main_gate_perimeter" \
  "SOV 38ALT Main Gate Perimeter"


echo -e "\n===================================================="
echo "✅ SICC (SOV 38ALT) VA Configuration Successfully Applied! (21 routes)"
echo "===================================================="
echo "Service:   $SERVICE_NAME -> $TARGET_URL"
echo "Consumer:  $CONSUMER_NAME ($SICC_USER)"
echo -e "\nAvailable Ingress Endpoints (Port 8088):"
echo "  • http://localhost:8088/va/sov-38alt-l4-icc-1-crowding"
echo "  • http://localhost:8088/va/sov-38alt-l4-lift-lobby-loitering"
echo "  • http://localhost:8088/va/sov-38alt-main-gate-smoking"
echo "  • http://localhost:8088/va/sov-38alt-main-gate-fire"
echo "  • http://localhost:8088/va/sov-38alt-carpark-lot-1-illegal-parking"
echo "  • http://localhost:8088/va/sov-38alt-l1-lift-lobby-loitering"
echo "  • http://localhost:8088/va/sov-38alt-l4-corridor-o-s-war-room-loitering"
echo "  • http://localhost:8088/va/sov-38alt-l4-interlock-loitering"
echo "  • http://localhost:8088/va/sov-38alt-l5-corridor-loitering"
echo "  • http://localhost:8088/va/sov-38alt-side-fencing-intrusion"
echo "  • http://localhost:8088/va/sov-38alt-side-fencing-smoking"
echo "  • http://localhost:8088/va/sov-38alt-side-fencing-fire"
echo "  • http://localhost:8088/va/sov-38alt-roof-top-loitering"
echo "  • http://localhost:8088/va/sov-38alt-l2-lift-lobby-loitering"
echo "  • http://localhost:8088/va/sov-38alt-l3-lift-lobby-loitering"
echo "  • http://localhost:8088/va/sov-38alt-l2-main-lobby-loitering"
echo "  • http://localhost:8088/va/sov-38alt-l2-reception-loitering"
echo "  • http://localhost:8088/va/sov-38alt-main-road-loitering"
echo "  • http://localhost:8088/va/sov-38alt-l6-lift-lobby-loitering"
echo "  • http://localhost:8088/va/sov-38alt-l5-o-s-cyber-room-loitering"
echo "  • http://localhost:8088/va/sov-38alt-main-gate-perimeter-intrusion"
echo -e "\nExample Test Command:"
echo "curl -i -X GET http://localhost:8088/va/sov-38alt-l4-icc-1-crowding -u \"$SICC_USER:$SICC_PASS\""
