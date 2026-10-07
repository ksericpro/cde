#!/usr/bin/env bash
# ==============================================================================
# Automated Kong Gateway Setup Script for Proscalar Webhook Ingestion via n8n (Option C)
# ==============================================================================

set -e

ADMIN_URL="${KONG_ADMIN_URL:-http://localhost:8001}"
SERVICE_NAME="imops-proscalar-n8n-service"
ROUTE_NAME="proscalar-webhook-route"
CONSUMER_NAME="proscalar_webhook_client"
UPSTREAM_URL="${1:-http://n8n-server:5678/webhook/proscalar}"
PROSCALAR_USER="${2:-proscalar@gmail.com}"
PROSCALAR_PASS="${3:-fwpkyjcf2i8fcoP05yEz}"

echo "===================================================="
echo "🚀 Starting Proscalar -> n8n Kong Ingress Setup (Option C)"
echo "   Admin URL:       $ADMIN_URL"
echo "   n8n Upstream:    $UPSTREAM_URL"
echo "   Consumer:        $CONSUMER_NAME ($PROSCALAR_USER)"
echo "===================================================="

# 1. Create or Update Gateway Service
echo -e "\n[1/5] Configuring Gateway Service: $SERVICE_NAME..."
SERVICE_ID=$(curl -s -X GET "$ADMIN_URL/services/$SERVICE_NAME" | grep -o '"id":"[^"]*' | cut -d'"' -f4 || true)
if [ -n "$SERVICE_ID" ]; then
    echo "Service $SERVICE_NAME already exists (ID: $SERVICE_ID). Ensuring upstream URL..."
    curl -s -X PATCH "$ADMIN_URL/services/$SERVICE_NAME" \
        -H "Content-Type: application/json" \
        -d "{\"url\":\"$UPSTREAM_URL\"}" > /dev/null
else
    SERVICE_ID=$(curl -s -X POST "$ADMIN_URL/services" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$SERVICE_NAME\",\"url\":\"$UPSTREAM_URL\"}" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
    echo "Service $SERVICE_NAME created successfully (ID: $SERVICE_ID)."
fi

# 2. Create or Update Ingress Route
echo -e "\n[2/5] Configuring Ingress Route: $ROUTE_NAME..."
ROUTE_ID=$(curl -s -X GET "$ADMIN_URL/services/$SERVICE_NAME/routes/$ROUTE_NAME" | grep -o '"id":"[^"]*' | cut -d'"' -f4 || true)
if [ -n "$ROUTE_ID" ]; then
    echo "Route $ROUTE_NAME already exists (ID: $ROUTE_ID). Updating..."
    curl -s -X PATCH "$ADMIN_URL/routes/$ROUTE_ID" \
        -H "Content-Type: application/json" \
        -d '{"paths":["/api/proscalar/webhook"],"methods":["POST"],"strip_path":true}' > /dev/null
else
    ROUTE_ID=$(curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/routes" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$ROUTE_NAME\",\"paths\":[\"/api/proscalar/webhook\"],\"methods\":[\"POST\"],\"strip_path\":true}" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
    echo "Route $ROUTE_NAME created successfully (ID: $ROUTE_ID)."
fi

# 3. Configure Plugins
echo -e "\n[3/5] Attaching Security & Policy Plugins..."
PLUGINS=$(curl -s -X GET "$ADMIN_URL/services/$SERVICE_NAME/plugins")

# basic-auth
if ! echo "$PLUGINS" | grep -q '"name":"basic-auth"'; then
    curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
        -H "Content-Type: application/json" \
        -d '{"name":"basic-auth","config":{"hide_credentials":true}}' > /dev/null
    echo "Attached 'basic-auth' plugin (hide_credentials = true)."
else
    echo "'basic-auth' plugin already attached."
fi

# rate-limiting
if ! echo "$PLUGINS" | grep -q '"name":"rate-limiting"'; then
    curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
        -H "Content-Type: application/json" \
        -d '{"name":"rate-limiting","config":{"minute":120,"policy":"local"}}' > /dev/null
    echo "Attached 'rate-limiting' (120 req/min) plugin."
else
    echo "'rate-limiting' plugin already attached."
fi

# request-size-limiting
if ! echo "$PLUGINS" | grep -q '"name":"request-size-limiting"'; then
    curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
        -H "Content-Type: application/json" \
        -d '{"name":"request-size-limiting","config":{"allowed_payload_size":5}}' > /dev/null
    echo "Attached 'request-size-limiting' (5MB) plugin."
else
    echo "'request-size-limiting' plugin already attached."
fi

# correlation-id
if ! echo "$PLUGINS" | grep -q '"name":"correlation-id"'; then
    curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
        -H "Content-Type: application/json" \
        -d '{"name":"correlation-id","config":{"header_name":"X-Request-ID","generator":"uuid","echo_downstream":true}}' > /dev/null
    echo "Attached 'correlation-id' plugin (header: X-Request-ID)."
else
    echo "'correlation-id' plugin already attached."
fi

# request-transformer
if ! echo "$PLUGINS" | grep -q '"name":"request-transformer"'; then
    curl -s -X POST "$ADMIN_URL/services/$SERVICE_NAME/plugins" \
        -H "Content-Type: application/json" \
        -d '{"name":"request-transformer","config":{"add":{"headers":["X-Source:Kong-Proscalar-Gateway"]}}}' > /dev/null
    echo "Attached 'request-transformer' plugin (X-Source: Kong-Proscalar-Gateway)."
else
    echo "'request-transformer' plugin already attached."
fi

# 4. Create Consumer & Credentials
echo -e "\n[4/5] Configuring Consumer & Credentials..."
CONSUMER_ID=$(curl -s -X GET "$ADMIN_URL/consumers/$CONSUMER_NAME" | grep -o '"id":"[^"]*' | cut -d'"' -f4 || true)
if [ -z "$CONSUMER_ID" ]; then
    CONSUMER_ID=$(curl -s -X POST "$ADMIN_URL/consumers" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$CONSUMER_NAME\",\"custom_id\":\"vendor-proscalar-tu\"}" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
    echo "Consumer $CONSUMER_NAME created successfully."
else
    echo "Consumer $CONSUMER_NAME already exists (ID: $CONSUMER_ID)."
fi

# Basic Auth Credential
CREDS=$(curl -s -X GET "$ADMIN_URL/consumers/$CONSUMER_NAME/basic-auth")
if ! echo "$CREDS" | grep -q "\"username\":\"$PROSCALAR_USER\""; then
    curl -s -X POST "$ADMIN_URL/consumers/$CONSUMER_NAME/basic-auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$PROSCALAR_USER\",\"password\":\"$PROSCALAR_PASS\"}" > /dev/null
    echo "Added basic-auth credentials ($PROSCALAR_USER)."
else
    echo "Credentials for $PROSCALAR_USER already configured."
fi

echo -e "\n[5/5] Provisioning Complete! Summary:"
echo "----------------------------------------------------"
echo "Ingress Endpoint:  POST http://localhost:8088/api/proscalar/webhook"
echo "Upstream Target:   $UPSTREAM_URL"
echo "Auth Mechanism:    HTTP Basic Auth ($PROSCALAR_USER)"
echo "===================================================="
