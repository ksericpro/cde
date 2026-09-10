#!/usr/bin/env bash
# =============================================================================
#  enable_kong_prometheus.sh — Enable Prometheus Plugin globally on Kong Gateway
# =============================================================================
set -euo pipefail

KONG_ADMIN_URL="${1:-http://localhost:8001}"

echo "================================================================="
echo "  Enabling Prometheus Metrics Plugin on Kong Gateway             "
echo "  Target Admin API: ${KONG_ADMIN_URL}                            "
echo "================================================================="

# Check Kong Admin API reachability
if ! curl -s -f -o /dev/null "${KONG_ADMIN_URL}/status"; then
  echo "[-] ERROR: Kong Admin API is not reachable at ${KONG_ADMIN_URL}"
  exit 1
fi

echo "[*] Checking if 'prometheus' plugin is already enabled..."
EXISTING_PLUGIN_ID=$(curl -s "${KONG_ADMIN_URL}/plugins" | grep -o '"id":"[^"]*","name":"prometheus"' | head -n1 | cut -d'"' -f4 || true)

if [ -n "${EXISTING_PLUGIN_ID}" ]; then
  echo "[+] Prometheus plugin already exists (ID: ${EXISTING_PLUGIN_ID}). Updating configuration..."
  curl -s -X PATCH "${KONG_ADMIN_URL}/plugins/${EXISTING_PLUGIN_ID}" \
    -d "config.status_code_metrics=true" \
    -d "config.latency_metrics=true" \
    -d "config.bandwidth_metrics=true" \
    -d "config.upstream_health_metrics=true" > /dev/null
else
  echo "[+] Enabling global Prometheus plugin..."
  curl -s -X POST "${KONG_ADMIN_URL}/plugins" \
    -d "name=prometheus" \
    -d "config.status_code_metrics=true" \
    -d "config.latency_metrics=true" \
    -d "config.bandwidth_metrics=true" \
    -d "config.upstream_health_metrics=true" > /dev/null
fi

echo "[+] Verifying /metrics scraping endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${KONG_ADMIN_URL}/metrics")

if [ "${HTTP_CODE}" -eq 200 ]; then
  echo "[+] SUCCESS: Kong /metrics endpoint responded with HTTP 200 OK."
  echo "    Sample metric:"
  curl -s "${KONG_ADMIN_URL}/metrics" | grep -E "^(kong_http_requests_total|kong_latency_bucket)" | head -n 3 || true
else
  echo "[-] WARNING: Received HTTP ${HTTP_CODE} from ${KONG_ADMIN_URL}/metrics"
fi

echo "================================================================="
