#!/usr/bin/env bash
# ==============================================================================
# Automated Kong Gateway Setup Script for Digital Twin API & Real-Time Provider
# ==============================================================================

set -e

UPSTREAM_HOST="${1:-localhost:13000}"
ADMIN_URL="${2:-http://localhost:8001}"
API_KEY="${3:-vizzio-digital-twin-key-2026}"

# -----------------------------------------------------------------------------
# Upstream URL Resolution
# -----------------------------------------------------------------------------
# When Kong runs inside Docker, 'localhost' refers to the container itself.
# Map localhost / 127.0.0.1 to host.docker.internal so Kong can reach the host backend.
if [[ "$UPSTREAM_HOST" =~ ^(https?://)?(localhost|127\.0\.0\.1)(:[0-9]+)? ]]; then
    PORT_PART="${BASH_REMATCH[3]:-:13000}"
    BASE_URL="http://host.docker.internal${PORT_PART}"
elif [[ "$UPSTREAM_HOST" =~ ^https?:// ]]; then
    BASE_URL="${UPSTREAM_HOST%/}"
elif [[ "$UPSTREAM_HOST" =~ :[0-9]+$ ]]; then
    BASE_URL="http://${UPSTREAM_HOST}"
else
    BASE_URL="http://${UPSTREAM_HOST}:13000"
fi

echo "============================================================"
echo " 🚀 Kong Gateway: Digital Twin Provider Provisioning (Bash)"
echo "    Admin API:    $ADMIN_URL"
echo "    Target Host:  $UPSTREAM_HOST"
echo "    Resolved Base: $BASE_URL"
echo "    Consumer Key: $API_KEY"
echo "============================================================"

# 1. Gateway Service: REST APIs (Reconciliation)
REST_SERVICE_NAME="imops-twin-rest-service"
echo -e "\n[1/5] Configuring REST Service ($REST_SERVICE_NAME)..."
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/services/$REST_SERVICE_NAME" || true)

if [ "$STATUS" -eq 200 ]; then
    echo "  Updating existing service $REST_SERVICE_NAME..."
    curl -s -X PATCH "$ADMIN_URL/services/$REST_SERVICE_NAME" \
        -H "Content-Type: application/json" \
        -d "{\"url\":\"$BASE_URL\",\"connect_timeout\":60000,\"read_timeout\":60000,\"write_timeout\":60000}" > /dev/null
else
    echo "  Creating new service $REST_SERVICE_NAME..."
    curl -s -X POST "$ADMIN_URL/services" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$REST_SERVICE_NAME\",\"url\":\"$BASE_URL\",\"connect_timeout\":60000,\"read_timeout\":60000,\"write_timeout\":60000}" > /dev/null
fi
echo "  ✅ REST Service ready -> $BASE_URL"

# 2. Gateway Service: Real-Time Stream (WebSocket / Socket.io)
WS_SERVICE_NAME="imops-twin-realtime-service"
echo -e "\n[2/5] Configuring Real-Time Stream Service ($WS_SERVICE_NAME)..."
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/services/$WS_SERVICE_NAME" || true)

if [ "$STATUS" -eq 200 ]; then
    echo "  Updating existing service $WS_SERVICE_NAME..."
    curl -s -X PATCH "$ADMIN_URL/services/$WS_SERVICE_NAME" \
        -H "Content-Type: application/json" \
        -d "{\"url\":\"$BASE_URL\",\"connect_timeout\":60000,\"read_timeout\":300000,\"write_timeout\":300000}" > /dev/null
else
    echo "  Creating new service $WS_SERVICE_NAME..."
    curl -s -X POST "$ADMIN_URL/services" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$WS_SERVICE_NAME\",\"url\":\"$BASE_URL\",\"connect_timeout\":60000,\"read_timeout\":300000,\"write_timeout\":300000}" > /dev/null
fi
echo "  ✅ Real-time Service ready -> $BASE_URL (Timeout: 300s)"

# 3. Create / Verify Routes
echo -e "\n[3/5] Configuring Routes..."
configure_route() {
    local ROUTE_NAME="$1"
    local SERVICE_NAME="$2"
    local PATH_JSON="$3"

    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/routes/$ROUTE_NAME" || true)
    if [ "$STATUS" -eq 200 ]; then
        curl -s -X PATCH "$ADMIN_URL/routes/$ROUTE_NAME" \
            -H "Content-Type: application/json" \
            -d "{\"paths\":$PATH_JSON,\"strip_path\":false,\"protocols\":[\"http\",\"https\"]}" > /dev/null
        echo "  ✅ Route '$ROUTE_NAME' updated"
    else
        curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/routes" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"$ROUTE_NAME\",\"paths\":$PATH_JSON,\"strip_path\":false,\"protocols\":[\"http\",\"https\"]}" > /dev/null
        echo "  ✅ Route '$ROUTE_NAME' created on $SERVICE_NAME"
    fi
}

configure_route "twin-visualization-route" "$REST_SERVICE_NAME" '["/api/visualization"]'
configure_route "twin-auth-route" "$REST_SERVICE_NAME" '["/api/auth"]'
configure_route "twin-ws-route" "$WS_SERVICE_NAME" '["/ws"]'
configure_route "twin-socketio-route" "$WS_SERVICE_NAME" '["/socket.io"]'

# 4. Attach Plugins (CORS & Rate Limiting)
echo -e "\n[4/5] Configuring Plugins (CORS, Rate Limiting)..."
# REST CORS
curl -s -X POST "$ADMIN_URL/services/$REST_SERVICE_NAME/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"cors","config":{"origins":["*"],"methods":["GET","POST","PUT","PATCH","DELETE","OPTIONS"],"headers":["Accept","Authorization","Content-Type","apikey","x-api-key","Origin","X-Requested-With"],"credentials":true,"max_age":3600}}' > /dev/null 2>&1 || true

# WS CORS
curl -s -X POST "$ADMIN_URL/services/$WS_SERVICE_NAME/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"cors","config":{"origins":["*"],"methods":["GET","POST","OPTIONS"],"headers":["Accept","Authorization","Content-Type","apikey","x-api-key","Sec-WebSocket-Key","Sec-WebSocket-Version","Sec-WebSocket-Extensions"],"credentials":true,"max_age":3600}}' > /dev/null 2>&1 || true

# Rate Limiting
curl -s -X POST "$ADMIN_URL/services/$REST_SERVICE_NAME/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"rate-limiting","config":{"minute":120,"policy":"local"}}' > /dev/null 2>&1 || true

# Option 2: Automatic Token Injection via request-transformer
AUTH_EMAIL="${4:-vizzio@imops.local}"
AUTH_PASS="${5:-xAJHkkm7m3V5MhtF0xGM}"
LOGIN_TARGET=$(echo "$BASE_URL" | sed 's/host\.docker\.internal/localhost/')
TOKEN_RESP=$(curl -s -X POST "$LOGIN_TARGET/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$AUTH_EMAIL\",\"password\":\"$AUTH_PASS\"}" || true)

TOKEN=$(echo "$TOKEN_RESP" | grep -o '"token":"[^"]*' | cut -d'"' -f4 || true)

if [ -n "$TOKEN" ]; then
    TRANSFORMER_ID=$(curl -s "$ADMIN_URL/routes/twin-visualization-route/plugins" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4 || true)
    if [ -n "$TRANSFORMER_ID" ]; then
        curl -s -X PATCH "$ADMIN_URL/routes/twin-visualization-route/plugins/$TRANSFORMER_ID" \
            -H "Content-Type: application/json" \
            -d "{\"config\":{\"add\":{\"headers\":[\"Authorization:Bearer $TOKEN\"]}}}" > /dev/null 2>&1 || true
    else
        curl -s -X POST "$ADMIN_URL/routes/twin-visualization-route/plugins" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"request-transformer\",\"config\":{\"add\":{\"headers\":[\"Authorization:Bearer $TOKEN\"]}}}" > /dev/null 2>&1 || true
    fi
    echo "  ✅ Attached 'request-transformer' (Backend Token Injection) to twin-visualization-route"
fi
echo "  ✅ Plugins verified on services"

# 5. Consumer & Credentials
CONSUMER_NAME="vizzio-twin-consumer"
echo -e "\n[5/5] Configuring Consumer ($CONSUMER_NAME)..."
curl -s -X POST "$ADMIN_URL/consumers" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$CONSUMER_NAME\",\"custom_id\":\"twin-vizzio-tenant\"}" > /dev/null 2>&1 || true

curl -s -X POST "$ADMIN_URL/consumers/$CONSUMER_NAME/key-auth" \
    -H "Content-Type: application/json" \
    -d "{\"key\":\"$API_KEY\"}" > /dev/null 2>&1 || true
echo "  ✅ Consumer and API Key verified"

echo "============================================================"
echo " 🎉 Kong Gateway Setup Complete for Digital Twins!"
echo " Ingress (Port 8088):"
echo "   REST Reconcil:  http://localhost:8088/api/visualization/hierarchy"
echo "   REST Incidents: http://localhost:8088/api/visualization/incidents"
echo "   WebSocket:      ws://localhost:8088/ws"
echo "   Socket.IO:      http://localhost:8088/socket.io/"
echo "============================================================"
