#!/usr/bin/env bash
# ==============================================================================
# Automated Kong Gateway & CDE Adapter Setup Script for BACnet Edge Ingestion
# (zaarr-bacnet-gw-01 -> Kong :8088 -> CDE Adapter :8090 -> iMOPS)
#
# Usage:
#   ./setup_bacnet_ingestion.sh [IMOPS_IP] [API_KEY] [KONG_ADMIN_URL] [ADAPTER_ADMIN_URL]
# Example:
#   ./setup_bacnet_ingestion.sh 10.65.51.252
# ==============================================================================

set -e

IMOPS_IP="${1:-localhost:13000}"
API_KEY="${2:-zaarr-bacnet-gw01-key-2026}"
ADMIN_URL="${3:-http://localhost:8001}"
ADAPTER_ADMIN_URL="${4:-http://localhost:8090}"
ADAPTER_UPSTREAM_URL="${5:-http://cde-datamart-etl:8090}"

# -----------------------------------------------------------------------------
# 0. Resolve Target iMOPS Base URL from IMOPS_IP parameter
# -----------------------------------------------------------------------------
if [[ "$IMOPS_IP" =~ ^(https?://)?(localhost|127\.0\.0\.1)(:[0-9]+)? ]]; then
    PORT_PART="${BASH_REMATCH[3]:-:13000}"
    IMOPS_BASE_URL="http://host.docker.internal${PORT_PART}"
elif [[ "$IMOPS_IP" =~ ^https?:// ]]; then
    IMOPS_BASE_URL="${IMOPS_IP%/}"
elif [[ "$IMOPS_IP" =~ :[0-9]+$ ]]; then
    IMOPS_BASE_URL="http://${IMOPS_IP}"
else
    IMOPS_BASE_URL="http://${IMOPS_IP}:13000"
fi

SERVICE_NAME="cde-bacnet-adapter-service"
CONSUMER_NAME="zaarr-bacnet-gw-01"

echo "=================================================================="
echo " 🚀 Starting CDE BACnet Ingestion & Transformation Setup (Bash)"
echo "    Kong Admin API:     $ADMIN_URL"
echo "    CDE Adapter Target: $ADAPTER_UPSTREAM_URL"
echo "    iMOPS Input Param:  $IMOPS_IP"
echo "    Resolved iMOPS URL: $IMOPS_BASE_URL"
echo "    Edge Gateway ID:    $CONSUMER_NAME"
echo "    X-API-Key Secret:   $API_KEY"
echo "=================================================================="

# 1. Configure Kong Service
echo -e "\n[1/5] Configuring Kong Service ($SERVICE_NAME)..."
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/services/$SERVICE_NAME" || true)
if [ "$STATUS" -eq 200 ]; then
    curl -s -X PATCH "$ADMIN_URL/services/$SERVICE_NAME" \
        -H "Content-Type: application/json" \
        -d "{\"url\":\"$ADAPTER_UPSTREAM_URL\",\"connect_timeout\":10000,\"read_timeout\":30000,\"write_timeout\":30000}" > /dev/null
    echo "  ✅ Updated service '$SERVICE_NAME' -> $ADAPTER_UPSTREAM_URL"
else
    curl -s -X POST "$ADMIN_URL/services" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$SERVICE_NAME\",\"url\":\"$ADAPTER_UPSTREAM_URL\",\"connect_timeout\":10000,\"read_timeout\":30000,\"write_timeout\":30000}" > /dev/null
    echo "  ✅ Created service '$SERVICE_NAME' -> $ADAPTER_UPSTREAM_URL"
fi

# 2. Configure Kong Routes
echo -e "\n[2/5] Configuring BACnet Ingress Routes..."
configure_route() {
    local ROUTE_NAME="$1"
    local PATH_STR="$2"
    local METHODS_JSON="$3"

    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/routes/$ROUTE_NAME" || true)
    if [ "$STATUS" -eq 200 ]; then
        curl -s -X PATCH "$ADMIN_URL/routes/$ROUTE_NAME" \
            -H "Content-Type: application/json" \
            -d "{\"paths\":[\"$PATH_STR\"],\"methods\":$METHODS_JSON,\"strip_path\":false,\"protocols\":[\"http\",\"https\"]}" > /dev/null
        echo "  ✅ Updated route '$ROUTE_NAME' ($PATH_STR)"
    else
        curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/routes" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"$ROUTE_NAME\",\"paths\":[\"$PATH_STR\"],\"methods\":$METHODS_JSON,\"strip_path\":false,\"protocols\":[\"http\",\"https\"]}" > /dev/null
        echo "  ✅ Created route '$ROUTE_NAME' ($PATH_STR)"
    fi
}

configure_route "bacnet-telemetry-route" "/api/v1/bacnet/telemetry" '["POST","OPTIONS"]'
configure_route "bacnet-devices-route"   "/api/v1/bacnet/devices"   '["POST","OPTIONS"]'
configure_route "bacnet-status-route"    "/api/v1/bacnet/status"    '["GET","OPTIONS"]'

# 3. Attach Security & Traffic Plugins
echo -e "\n[3/5] Attaching Security & Traffic Plugins..."
curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"key-auth","config":{"key_names":["X-API-Key","x-api-key","apikey"],"hide_credentials":true,"key_in_header":true,"key_in_query":true}}' > /dev/null 2>&1 || true

curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"rate-limiting","config":{"minute":600,"policy":"local"}}' > /dev/null 2>&1 || true

curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"request-size-limiting","config":{"allowed_payload_size":5}}' > /dev/null 2>&1 || true

curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"correlation-id","config":{"header_name":"X-Request-ID","generator":"uuid","echo_downstream":true}}' > /dev/null 2>&1 || true
echo "  ✅ Attached key-auth, rate-limiting (600/min), request-size-limiting (5MB), correlation-id"

# 4. Configure Consumer & X-API-Key
echo -e "\n[4/5] Configuring Consumer ($CONSUMER_NAME) & X-API-Key..."
curl -s -X POST "$ADMIN_URL/consumers" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$CONSUMER_NAME\",\"custom_id\":\"smart-nation-bacnet-gw-01\"}" > /dev/null 2>&1 || true

curl -s -X POST "$ADMIN_URL/consumers/$CONSUMER_NAME/key-auth" \
    -H "Content-Type: application/json" \
    -d "{\"key\":\"$API_KEY\"}" > /dev/null 2>&1 || true
echo "  ✅ Consumer '$CONSUMER_NAME' ready with X-API-Key"

# 5. Update CDE Adapter Outbound iMOPS Target URL
echo -e "\n[5/5] Updating CDE BACnet Adapter Target iMOPS URL ($IMOPS_BASE_URL)..."
curl -s -X POST "$ADAPTER_ADMIN_URL/api/v1/bacnet/config" \
    -H "Content-Type: application/json" \
    -d "{\"imopsBaseUrl\":\"$IMOPS_BASE_URL\"}" > /dev/null || true
echo "  ✅ CDE Adapter outbound iMOPS target set to: $IMOPS_BASE_URL"

echo -e "\n=================================================================="
echo " Deliverables for Edge Gateway Setup (zaarr-bacnet-gw-01)"
echo "------------------------------------------------------------------"
echo " 1. CDE API Gateway base_url:  http://localhost:8088 (or https://<CDE_HOST>:8443)"
echo " 2. Confirmed Paths:"
echo "      - Telemetry Batch:       POST /api/v1/bacnet/telemetry"
echo "      - Controller Status:     POST /api/v1/bacnet/devices"
echo "      - Adapter Live Status:   GET  /api/v1/bacnet/status"
echo " 3. X-API-Key Secret:          $API_KEY"
echo " 4. Outbound iMOPS Target:     $IMOPS_BASE_URL"
echo "=================================================================="

